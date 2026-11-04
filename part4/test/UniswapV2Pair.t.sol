// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {Test} from "forge-std/Test.sol";
import {IUniswapV2Factory} from "../src/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../src/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2ERC20} from "../src/contracts/interfaces/IUniswapV2ERC20.sol";
import {IUniswapV2Router01} from "../src/contracts/interfaces/IUniswapV2Router01.sol";
import {console2} from "forge-std/console2.sol";

contract UniswapV2PairTest is BaseTest {
    function test_mint_initialLiquidity() public {
        uint256 amount0 = 10_000e18;
        uint256 amount1 = 40_000e18;

        uint256 liquidity = _addLiquidityDirect(alice, amount0, amount1);

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
        _addLiquidityDirect(alice, 10_000e18, 40_000e18);

        // same 1:4 ratio as the pool
        uint256 amount0 = 1_000e18;
        uint256 amount1 = 4_000e18;

        uint256 liquidity = _addLiquidityDirect(bob, amount0, amount1);

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

            uint256 minted = _addLiquidityDirect(lps[i], deposits0[i], deposits1[i]);

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

    //     uint256 aliceLiquidity = _addLiquidityDirect(alice, amount0, amount1);
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
        uint256 aliceLiquidity = _addLiquidityDirect(alice, 10_000e18, 40_000e18);

        // Bob provides additional liquidity at the same ratio.
        uint256 bobLiquidity = _addLiquidityDirect(bob, 1_000e18, 4_000e18);

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
        _addLiquidityDirect(alice, 10_000e18, 40_000e18);

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

    function test_mint_unbalancedLiquidity() public {
        // 1. Alice initializes the pool at a 1:4 ratio.
        uint256 aliceAmount0 = 10_000e18;
        uint256 aliceAmount1 = 40_000e18;

        uint256 aliceLiquidity = _addLiquidityDirect(alice, aliceAmount0, aliceAmount1);

        console2.log("=== INITIAL POOL ===");
        console2.log("Alice LP minted:", aliceLiquidity);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        console2.log("Reserve0:", uint256(reserve0));
        console2.log("Reserve1:", uint256(reserve1));
        console2.log("Total LP supply:", pair.totalSupply());

        // 2. Bob deposits at a different ratio (1:8 instead of 1:4).
        uint256 amount0 = 1_000e18;
        uint256 amount1 = 8_000e18;

        console2.log("=== BOB'S DEPOSIT ===");
        console2.log("Token0 deposited:", amount0);
        console2.log("Token1 deposited:", amount1);

        // 3. Calculate expected liquidity independently.
        uint256 supply = pair.totalSupply();

        uint256 liquidity0 = amount0 * supply / uint256(reserve0);
        uint256 liquidity1 = amount1 * supply / uint256(reserve1);

        console2.log("=== LIQUIDITY CALCULATION ===");
        console2.log("amount0 * totalSupply:", amount0 * supply);
        console2.log("Divided by reserve0:", uint256(reserve0));
        console2.log("Liquidity from token0:", liquidity0);

        console2.log("amount1 * totalSupply:", amount1 * supply);
        console2.log("Divided by reserve1:", uint256(reserve1));
        console2.log("Liquidity from token1:", liquidity1);

        uint256 expectedLiquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

        console2.log("Minimum liquidity:", expectedLiquidity);

        // 4. Bob transfers both tokens directly to the Pair and calls mint.
        uint256 bobLiquidity = _addLiquidityDirect(bob, amount0, amount1);

        console2.log("=== MINT RESULT ===");
        console2.log("Bob LP minted:", bobLiquidity);
        console2.log("Bob LP balance:", pair.balanceOf(bob));

        // 5. Verify the Pair used the smaller liquidity calculation.
        assertEq(bobLiquidity, expectedLiquidity, "liquidity minted");
        assertEq(bobLiquidity, 2_000e18, "expected 2000 LP");
        assertEq(pair.balanceOf(bob), 2_000e18, "bob LP balance");

        // 6. Verify the entire deposit was added to the reserves.
        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();

        console2.log("=== UPDATED RESERVES ===");
        console2.log("New reserve0:", uint256(newReserve0));
        console2.log("New reserve1:", uint256(newReserve1));

        assertEq(uint256(newReserve0), 11_000e18, "reserve0");
        assertEq(uint256(newReserve1), 48_000e18, "reserve1");

        // 7. Verify total supply.
        assertEq(pair.totalSupply(), 22_000e18, "total supply");

        // 8. Verify the excess Token1 remains in the Pair.
        uint256 excessToken1 = amount1 - (amount0 * uint256(reserve1) / uint256(reserve0));

        console2.log("=== EXCESS CONTRIBUTION ===");
        console2.log("Excess token1:", excessToken1);
        console2.log("Bob token1 balance:", token1.balanceOf(bob));
        console2.log("Pair token1 balance:", token1.balanceOf(address(pair)));

        assertEq(excessToken1, 4_000e18, "excess token1");
    }

    function test_swapExtractsExcessWETHWhenKCheckIsDisabled() public {
        // 1. Alice initializes the pool at 1 WETH : 2000 DAI.
        uint256 initialWETH = 10e18;
        uint256 initialDAI = 20_000e18;

        _addLiquidityDirect(alice, initialWETH, initialDAI);

        // 2. Record initial reserves and K.
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        uint256 kBefore = uint256(reserve0Before) * uint256(reserve1Before);

        // 3. Bob deposits only 2000 DAI.
        uint256 daiIn = 2_000e18;

        vm.startPrank(bob);
        token1.transfer(address(pair), daiIn);

        // 4. Bob requests 1.5 WETH.
        uint256 wethOut = 1.5e18;

        uint256 bobWETHBefore = token0.balanceOf(bob);

        pair.swap(wethOut, 0, bob, bytes(""));

        vm.stopPrank();

        // 5. Read updated reserves and calculate K.
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        uint256 kAfter = uint256(reserve0After) * uint256(reserve1After);

        // 6. Verify the extraction.
        assertEq(token0.balanceOf(bob), bobWETHBefore + wethOut, "Bob received 1.5 WETH");
        assertEq(uint256(reserve0After), 8.5 ether, "WETH reserve");
        assertEq(uint256(reserve1After), 22_000e18, "DAI reserve");
        // K should decrease because the K check is disabled.
        assertLt(kAfter, kBefore, "K should decrease");

        console2.log("=== SWAP RESULTS ===");
        console2.log("WETH received by Bob:", wethOut);
        console2.log("DAI deposited by Bob:", daiIn);
        console2.log("K before:", kBefore);
        console2.log("K after:", kAfter);
    }

    function test_swap_zero() public {
        // Arrange
        // add liquidity
        uint256 amount0 = 10_000e18;
        uint256 amount1 = 40_000e18;
        _addLiquidityDirect(alice, amount0, amount1);
        // get reserves
        // (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        // // send tokens to pair
        uint256 amount0In = 20e18;
        // uint256 amount1In = 20e18;
        vm.startPrank(bob);
        token0.transfer(address(pair), amount0In);
        // Act
        vm.expectRevert();
        pair.swap(0, 0, bob, bytes(""));
        // Assert
    }

    function test_swap_zeroFromGetAmountOutRounding() public {
        // Arrange
        _addLiquidityDirect(alice, 10_000e18, 40_000e18);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // 1 wei of token1 in -> token0 out:
        // (1 * 997 * 10_000e18) / (40_000e18 * 1000 + 997 * 1) ≈ 0.249 -> truncates to 0
        uint256 amount1In = 1;
        uint256 amount0Out = router.getAmountOut(amount1In, reserve1, reserve0);
        assertEq(amount0Out, 0, "sanity: output should round to 0");

        vm.startPrank(bob);
        token1.transfer(address(pair), amount1In);

        // Act + Assert
        vm.expectRevert();
        pair.swap(amount0Out, 0, bob, bytes(""));
        vm.stopPrank();
    }

    function test_swap_small_amounts() public {
        // Arrange
        // add liquidity
        uint256 amount0 = 10_000e18;
        uint256 amount1 = 40_000e18;
        _addLiquidityDirect(alice, amount0, amount1);
        uint256 amount0In = 100;
        // get reservers
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        // get amounts out
        (uint256 amount1Out) = router.getAmountOut(amount0In, reserve0Before, reserve1Before);
        // Act
        vm.startPrank(bob);
        token0.transfer(address(pair), amount0In);
        pair.swap(0, amount1Out, bob, bytes(""));
        // Assert
    }
}
