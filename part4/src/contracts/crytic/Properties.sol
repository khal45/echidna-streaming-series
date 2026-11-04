pragma solidity ^0.6.0;

import "./wrapper.sol";

contract UniswapV2PropertiesTest is Wrapper {
    // after a burn, LP token0/token1 should not increase by more than the expected amounts
    // function echidna_lp_never_withdraws_more_than_deposited() public view returns (bool) {
    //     return ghostWithdrawn0 <= ghostDeposited0 && ghostWithdrawn1 <= ghostDeposited1;
    // }
}
