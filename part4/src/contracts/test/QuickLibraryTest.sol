// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

// The uni-v2 sources compile with ^0.6.0 while forge-std needs >=0.8.13, so this
// test reaches the library through a 0.6 harness plus deployCode.
interface IUniswapV2LibraryHarness {
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        view
        returns (uint256 amountOut);
}

contract UniswapV2LibraryTest is Test {
    function testGetAmountOut() public {
        IUniswapV2LibraryHarness harness =
            IUniswapV2LibraryHarness(deployCode("UniswapV2LibraryHarness.sol:UniswapV2LibraryHarness"));

        harness.getAmountOut(20e18, 1000e18, 20e18);
    }
}
