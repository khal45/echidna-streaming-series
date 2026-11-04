// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2ERC20} from "../interfaces/IUniswapV2ERC20.sol";
import {IUniswapV2Router01} from "../interfaces/IUniswapV2Router01.sol";
import {console2} from "forge-std/Test.sol";

interface ITestERC20 is IUniswapV2ERC20 {
    function mint(address to, uint256 amount) external;
}

// The uni-v2 sources compile with 0.6 while forge-std needs >=0.8.13, so this
// test reaches the 0.6 contracts through their interfaces plus deployCode.
contract UniswapV2Router01Test is Test {
    IUniswapV2Factory factory;
    IUniswapV2Router01 router;
    IUniswapV2Pair pair;
    ITestERC20 token0;
    ITestERC20 token1;

    address lp = makeAddr("lp");
    address user = makeAddr("user");

    uint256 constant INITIAL_AMOUNT0 = 10_000e18;
    uint256 constant INITIAL_AMOUNT1 = 40_000e18;

    function setUp() public {
        factory = IUniswapV2Factory(deployCode("UniswapV2Factory.sol:UniswapV2Factory", abi.encode(address(this))));
        router = IUniswapV2Router01(
            deployCode("UniswapV2Router01.sol:UniswapV2Router01", abi.encode(address(factory), address(0)))
        );

        ITestERC20 tokenA = ITestERC20(deployCode("UniswapV2ERC20.sol:UniswapV2ERC20"));
        ITestERC20 tokenB = ITestERC20(deployCode("UniswapV2ERC20.sol:UniswapV2ERC20"));

        pair = IUniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));

        // the pair sorts tokens by address, so read the real token0/token1 back
        token0 = ITestERC20(pair.token0());
        token1 = ITestERC20(pair.token1());

        token0.mint(lp, INITIAL_AMOUNT0);
        token1.mint(lp, INITIAL_AMOUNT1);

        // Uniswap V2 pattern: transfer tokens to the pair first, then call mint
        vm.startPrank(lp);
        token0.transfer(address(pair), INITIAL_AMOUNT0);
        token1.transfer(address(pair), INITIAL_AMOUNT1);
        pair.mint(lp);
        vm.stopPrank();
    }

    function test_swapExactTokensForTokens() public {
        console2.log("user %s", user);
        uint256 amountIn = 1_000e18;

        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        uint256 expectedAmountOut = _getAmountOut(amountIn, reserve0Before, reserve1Before);

        token0.mint(user, amountIn);

        vm.startPrank(user);
        token0.approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, expectedAmountOut, path, user, block.timestamp);
        vm.stopPrank();

        assertEq(amounts.length, 2, "amounts length");
        assertEq(amounts[0], amountIn, "amount in");
        assertEq(amounts[1], expectedAmountOut, "amount out");

        assertEq(token0.balanceOf(user), 0, "user token0 balance");
        assertEq(token1.balanceOf(user), expectedAmountOut, "user token1 balance");

        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
        assertEq(uint256(reserve0After), uint256(reserve0Before) + amountIn, "reserve0 after");
        assertEq(uint256(reserve1After), uint256(reserve1Before) - expectedAmountOut, "reserve1 after");
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee);
    }
}
