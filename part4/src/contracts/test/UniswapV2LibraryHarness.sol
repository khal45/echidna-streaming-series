pragma solidity ^0.6.0;

import "../libraries/UniswapV2Library.sol";

// Exposes the 0.6 library to 0.8 Foundry tests through deployCode.
contract UniswapV2LibraryHarness {
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        view
        returns (uint256 amountOut)
    {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }
}
