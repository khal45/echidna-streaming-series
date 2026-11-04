// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";

contract UniswapV2RouterTest is BaseTest {
    function test_addLiquidity() public {
        uint256 amount0 = 10_000e18;
        uint256 amount1 = 40_000e18;
        (uint256 amountA, uint256 amountB, uint256 liquidity) = _addLiquidity(alice, amount0, amount1);

        assertEq(amountA, amount0);
        assertEq(amountB, amount1);
        assertGt(liquidity, 0);
        assertEq(pair.balanceOf(alice), liquidity);
    }

    function test_removeLiquidity() public {
        // Arrange
        // add liquidity
        uint256 amount0 = 10_000e18;
        uint256 amount1 = 40_000e18;
        (,, uint256 liquidity) = _addLiquidity(alice, amount0, amount1);

        uint256 balance0Before = token0.balanceOf(alice);
        uint256 balance1Before = token1.balanceOf(alice);

        // Act
        // remove liquidity
        (uint256 amountA, uint256 amountB) =
            _removeLiquidity(alice, address(token0), address(token1), liquidity, 0, 0, alice, block.timestamp + 1 hours);

        // Assert
        // lp tokens were burned
        assertEq(pair.balanceOf(alice), 0);

        // user got expected amounts after burning
        assertEq(token0.balanceOf(alice) - balance0Before, amountA);
        assertEq(token1.balanceOf(alice) - balance1Before, amountB);
        assertGt(amountA, 0);
        assertGt(amountB, 0);
    }
}
