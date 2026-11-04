pragma solidity ^0.8.0;
import {Test} from "forge-std/Test.sol";
import {Token} from "../src/exercise2/token.sol";

contract TokenTest is Test {
    Token token;

    function setUp() public {
        token = new Token();
    }

    function test_ReproduceEchidnaFailure() public {
        token.Owner();
        token.resume();
        assertFalse(token.isPaused());
    }
}

