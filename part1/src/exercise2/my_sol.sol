pragma solidity ^0.8.0;

// Add a property to check that the contract cannot be unpaused.
// Once Echidna finds the bug, fix the issue, and re-try your property with Echidna.
import {Token} from "./token.sol";

contract TestToken is Token {
    // setup
    // Consider paused() to be called at deployment, and the ownership removed.
    constructor() public {
        paused();
        // how do I remove the ownership?
        owner = address(0x0);
    }

    // property testing
    // function echidna_test_cannot_be_paused() public view returns (bool) {
    //     return is_paused;
    // }

    // assertion testing
    function testPausable() public {
        assert(is_paused);
    }
}
