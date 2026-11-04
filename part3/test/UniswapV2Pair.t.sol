// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IUniswapV2Factory} from "../src/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../src/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2ERC20} from "../src/contracts/interfaces/IUniswapV2ERC20.sol";
import {console2} from "forge-std/console2.sol";

// The uni-v2 sources compile with ^0.6.0 while forge-std needs >=0.8.13, so this
// test compiles with 0.8 and reaches the 0.6 contracts through their interfaces
// plus deployCode (which loads their already-compiled artifacts).
interface ITestERC20 is IUniswapV2ERC20 {
    function mint(address to, uint256 amount) external;
}

contract UniswapV2PairTest is Test {
    IUniswapV2Factory factory;
    IUniswapV2Pair pair;
    ITestERC20 token0;
    ITestERC20 token1;

    address feeToSetter = makeAddr("feeToSetter");
    address alice = makeAddr("alice"); // initial LP
    address bob = makeAddr("bob"); // subsequent LP

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public {
        factory = IUniswapV2Factory(deployCode("UniswapV2Factory.sol:UniswapV2Factory", abi.encode(feeToSetter)));

        ITestERC20 tokenA = ITestERC20(deployCode("UniswapV2ERC20.sol:UniswapV2ERC20"));
        ITestERC20 tokenB = ITestERC20(deployCode("UniswapV2ERC20.sol:UniswapV2ERC20"));

        pair = IUniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));

        // the pair sorts tokens by address, so read the real token0/token1 back
        token0 = ITestERC20(pair.token0());
        token1 = ITestERC20(pair.token1());

        token0.mint(alice, 1_000_000e18);
        token1.mint(alice, 1_000_000e18);
        token0.mint(bob, 1_000_000e18);
        token1.mint(bob, 1_000_000e18);
    }

    /// Uniswap V2 pattern: transfer tokens to the pair first, then call mint
    function _addLiquidity(address lp, uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        vm.startPrank(lp);
        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);
        liquidity = pair.mint(lp);
        vm.stopPrank();
    }

    function test_mint_initialLiquidity() public {
        uint256 amount0 = 10_000e18;
        uint256 amount1 = 40_000e18;

        uint256 liquidity = _addLiquidity(alice, amount0, amount1);

        // sqrt(10_000e18 * 40_000e18) = sqrt(4e44) = 2e22 = 20_000e18
        uint256 expectedLiquidity = 20_000e18 - MINIMUM_LIQUIDITY;

        assertEq(liquidity, expectedLiquidity, "liquidity");
        assertEq(pair.balanceOf(alice), expectedLiquidity, "alice LP");
        assertEq(pair.balanceOf(address(0)), MINIMUM_LIQUIDITY, "locked LP");
        assertEq(pair.totalSupply(), 20_000e18, "totalSupply");

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(uint256(r0), amount0, "reserve0");
        assertEq(uint256(r1), amount1, "reserve1");
    }

    function test_mint_subsequentLiquidity() public {
        _addLiquidity(alice, 10_000e18, 40_000e18);

        // same 1:4 ratio as the pool
        uint256 amount0 = 1_000e18;
        uint256 amount1 = 4_000e18;

        uint256 liquidity = _addLiquidity(bob, amount0, amount1);

        // min(1000e18 * 20000e18 / 10000e18, 4000e18 * 20000e18 / 40000e18) = 2000e18
        assertEq(liquidity, 2_000e18, "liquidity");
        assertEq(pair.balanceOf(bob), 2_000e18, "bob LP");
        assertEq(pair.totalSupply(), 22_000e18, "totalSupply");

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(uint256(r0), 11_000e18, "reserve0");
        assertEq(uint256(r1), 44_000e18, "reserve1");
    }

    function test_burnOneOfTenLPs() public {
        address[] memory lps = new address[](10);
        uint256[] memory deposits0 = new uint256[](10);
        uint256[] memory deposits1 = new uint256[](10);

        // Ten LPs deposit different amounts at a 1:4 ratio.
        for (uint256 i = 0; i < 10; i++) {
            lps[i] = makeAddr(string.concat("lp", vm.toString(i)));

            deposits0[i] = (100 + i * 100) * 1e18;
            deposits1[i] = deposits0[i] * 4;

            token0.mint(lps[i], deposits0[i]);
            token1.mint(lps[i], deposits1[i]);

            uint256 minted = _addLiquidity(lps[i], deposits0[i], deposits1[i]);

            console2.log("LP index:", i);
            console2.log("Token0 deposited:", deposits0[i]);
            console2.log("Token1 deposited:", deposits1[i]);
            console2.log("LP tokens minted:", minted);
        }

        // LP 5 will redeem their position.
        address lp = lps[5];

        uint256 lpToken0Before = token0.balanceOf(lp);
        uint256 lpToken1Before = token1.balanceOf(lp);

        // Record the pair's balances before transferring LP tokens.
        uint256 pairBalance0 = token0.balanceOf(address(pair));
        uint256 pairBalance1 = token1.balanceOf(address(pair));

        console2.log("=== BEFORE BURN ===");
        console2.log("Pair balance0:", pairBalance0);
        console2.log("Pair balance1:", pairBalance1);

        // Transfer this LP's tokens to the pair.
        uint256 lpLiquidity = pair.balanceOf(lp);

        vm.prank(lp);
        pair.transfer(address(pair), lpLiquidity);

        uint256 pairLpBefore = pair.balanceOf(address(pair));
        uint256 totalSupplyBefore = pair.totalSupply();

        console2.log("Liquidity to burn:", pairLpBefore);
        console2.log("Total supply before:", totalSupplyBefore);

        // Calculate the expected pro-rata amounts independently.
        uint256 expected0 = lpLiquidity * pairBalance0 / totalSupplyBefore;

        uint256 expected1 = lpLiquidity * pairBalance1 / totalSupplyBefore;

        // Burn the LP tokens and redeem the underlying assets.
        vm.prank(lp);
        (uint256 amount0, uint256 amount1) = pair.burn(lp);

        console2.log("=== BURN CALCULATION ===");
        console2.log("amount0:", amount0);
        console2.log("amount1:", amount1);

        // Verify the burn calculation.
        assertEq(amount0, expected0, "amount0 calculation");
        assertEq(amount1, expected1, "amount1 calculation");

        // Verify the LP received the tokens returned by burn().
        uint256 lpToken0After = token0.balanceOf(lp);
        uint256 lpToken1After = token1.balanceOf(lp);

        uint256 received0 = lpToken0After - lpToken0Before;
        uint256 received1 = lpToken1After - lpToken1Before;

        assertEq(received0, amount0, "token0 received");
        assertEq(received1, amount1, "token1 received");

        console2.log("=== TOKENS RECEIVED ===");
        console2.log("Token0 received:", received0);
        console2.log("Token1 received:", received1);

        // Verify the pair burned the LP tokens held by the pair.
        uint256 pairLpAfter = pair.balanceOf(address(pair));

        assertEq(pairLpBefore - pairLpAfter, lpLiquidity);
        assertEq(pairLpAfter, 0);

        console2.log("=== PAIR LP BALANCE ===");
        console2.log("Before:", pairLpBefore);
        console2.log("After:", pairLpAfter);

        // Verify total LP supply decreased by the burned liquidity.
        uint256 totalSupplyAfter = pair.totalSupply();

        assertEq(totalSupplyBefore - totalSupplyAfter, lpLiquidity, "total supply reduction");

        console2.log("=== TOTAL LP SUPPLY ===");
        console2.log("Before:", totalSupplyBefore);
        console2.log("After:", totalSupplyAfter);
    }

    // Replay of the Echidna failure: testBurnDecreasesLpSupply(0,0,0).
    // The fuzzed zeros are clamped to MIN_DEPOSIT (1e12), so the pair is
    // bootstrapped with 1e12 of each token and only 1 wei of LP is burned.
    // With `_burn` removed, burn does NOT decrease the LP supply.
    // function test_burnDoesNotDecreaseLpSupply() public {
    //     uint256 amount0 = 1e12;
    //     uint256 amount1 = 1e12;

    //     uint256 aliceLiquidity = _addLiquidity(alice, amount0, amount1);
    //     assertEq(aliceLiquidity, 1e12 - MINIMUM_LIQUIDITY, "initial liquidity");
    //     assertEq(pair.totalSupply(), 1e12, "initial totalSupply");

    //     uint256 totalSupplyBefore = pair.totalSupply();
    //     uint256 liquidityToBurn = 1;

    //     assertEq(pair.balanceOf(alice), aliceLiquidity, "alice LP before");
    //     assertEq(aliceLiquidity - liquidityToBurn, 999_999_998_999, "burn is the smallest unit");

    //     vm.prank(alice);
    //     pair.transfer(address(pair), liquidityToBurn);
    //     assertEq(pair.balanceOf(address(pair)), liquidityToBurn, "pair LP before burn");

    //     vm.prank(alice);
    //     (uint256 amount0Out, uint256 amount1Out) = pair.burn(alice);

    //     assertEq(amount0Out, 1, "token0 out");
    //     assertEq(amount1Out, 1, "token1 out");
    //     assertEq(pair.totalSupply(), totalSupplyBefore, "LP supply did not decrease");
    //     assertEq(pair.balanceOf(address(pair)), liquidityToBurn, "pair LP was not burned");
    // }

    function test_bobCanRedeemAlicesAndHisOwnLiquidity() public {
        // Alice provides initial liquidity.
        uint256 aliceLiquidity = _addLiquidity(alice, 10_000e18, 40_000e18);

        // Bob provides additional liquidity at the same ratio.
        uint256 bobLiquidity = _addLiquidity(bob, 1_000e18, 4_000e18);

        // Both users transfer their LP tokens directly to the pair.
        vm.prank(alice);
        pair.transfer(address(pair), aliceLiquidity);

        vm.prank(bob);
        pair.transfer(address(pair), bobLiquidity);

        uint256 totalLiquidity = aliceLiquidity + bobLiquidity;

        // The pair now holds both users' LP tokens.
        assertEq(pair.balanceOf(address(pair)), totalLiquidity, "pair holds both positions");

        uint256 bobBalance0Before = token0.balanceOf(bob);
        uint256 bobBalance1Before = token1.balanceOf(bob);

        // Bob calls burn directly, without the Router.
        vm.prank(bob);
        (uint256 amount0, uint256 amount1) = pair.burn(bob);

        // Bob receives the underlying tokens for BOTH positions.
        assertEq(token0.balanceOf(bob), bobBalance0Before + amount0, "bob receives token0");

        assertEq(token1.balanceOf(bob), bobBalance1Before + amount1, "bob receives token1");

        // Alice's LP tokens were also burned.
        assertEq(pair.balanceOf(alice), 0, "alice LP balance");
        assertEq(pair.balanceOf(bob), 0, "bob LP balance");
        assertEq(pair.balanceOf(address(pair)), 0, "pair LP balance");

        // Only the permanently locked minimum liquidity remains.
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY);

        console2.log("Alice LP deposited:", aliceLiquidity);
        console2.log("Bob LP deposited:", bobLiquidity);
        console2.log("Total LP burned:", totalLiquidity);
        console2.log("Token0 sent to Bob:", amount0);
        console2.log("Token1 sent to Bob:", amount1);
    }

    function test_swap_calculatesBothInputs() public {
        // 1. Alice provides initial liquidity.
        _addLiquidity(alice, 10_000e18, 40_000e18);

        // 2. Read the reserves before the swap.
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        console2.log("=== RESERVES BEFORE SWAP ===");
        console2.log("reserve0:", uint256(reserve0));
        console2.log("reserve1:", uint256(reserve1));

        // 3. Bob transfers both input tokens to the pair.
        uint256 amount0In = 20e18;
        uint256 amount1In = 20e18;

        vm.startPrank(bob);

        token0.transfer(address(pair), amount0In);
        token1.transfer(address(pair), amount1In);

        // 4. Bob requests nonzero output amounts for both tokens.
        uint256 amount0Out = 10e18;
        uint256 amount1Out = 10e18;

        // // where's token0 & token1
        // console2.log("balance0 before swap %s", ITestERC20(token0).balanceOf(address(pair)));
        // console2.log("balance1 before swap %s", ITestERC20(token1).balanceOf(address(pair)));

        console2.log("=== AMOUNTS REQUESTED ===");
        console2.log("amount0Out:", amount0Out);
        console2.log("amount1Out:", amount1Out);

        // 5. Execute the swap.
        // The pair's internal console2 logs will show the calculations.
        pair.swap(amount0Out, amount1Out, bob, bytes(""));

        vm.stopPrank();

        console2.log("=== SWAP FINISHED ===");
        console2.log("Bob token0 balance:", token0.balanceOf(bob));
        console2.log("Bob token1 balance:", token1.balanceOf(bob));
    }
}
