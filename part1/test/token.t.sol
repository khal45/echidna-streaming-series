// // SPDX-License-Identifier: MIT
// pragma solidity ^0.7.0;

// import "forge-std/Test.sol";
// import "../src/token.sol";

// contract TokenTest is Test {
//     Token token;

//     address echidnaCaller = address(0x123);
//     address attacker = address(0x0);

//     function setUp() public {
//         token = new Token();
//         address echidna_caller = msg.sender;
//         balances[echidna_caller] = 10000;
//     }

//     function test_ReproduceEchidnaFailure() public {
//         vm.prank(echidnaCaller);

//         // Transfer more than the caller owns
//         TestToken.transfer(0x0, 10006);

//         // Echidna property is now broken
//         assertLe(token.balances(echidnaCaller), 10000);
//     }
// }
