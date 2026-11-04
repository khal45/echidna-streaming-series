// SPDX-License-Identifier: BSD-4-Clause
pragma solidity ^0.8.1;

import {Test} from "forge-std/Test.sol";
import {ABDKMath64x64} from "../../abdk/ABDKMath64x64.sol";
import {console2} from "forge-std/console2.sol";

contract ABDKMathMulTest is Test {
    // Replicates the Echidna counterexample:
    // mul_test_associative_property(int128,int128,int128) falsified with (1, 1, -1)
    // Reason: ErrorRevert (assertion failure: (1 * 1) * -1 != 1 * (1 * -1))
    function testMulAssociativePropertyEchidnaCounterexample() public {
        // Raw 64.64 values as fed by Echidna, not fromInt values
        int128 x = 1;
        int128 y = 1;
        int128 z = -1;

        int128 x_y = ABDKMath64x64.mul(x, y);
        int128 xy_z = ABDKMath64x64.mul(x_y, z);
        int128 y_z = ABDKMath64x64.mul(y, z);
        int128 x_yz = ABDKMath64x64.mul(x, y_z);

        console2.log("x_y %s", x_y);
        console2.log("xy_z %s", xy_z);
        console2.log("y_z %s", y_z);
        console2.log("x_yz %s", x_yz);
    }

    function testMulPrecisionLoss() public {
        // converts one and three to int128
        int128 one = ABDKMath64x64.fromInt(1);
        int128 three = ABDKMath64x64.fromInt(3);
        // 1/3 * 3
        int128 oneThird = ABDKMath64x64.divi(1, 3);
        int128 result = ABDKMath64x64.mul(oneThird, three);
        console2.log("one %s", one);
        console2.log("result %s", result);
        assertNotEq(result, one, "Expected precision loss");
    }

    function testMulOperation() public {
        int128 x = ABDKMath64x64.fromInt(10);
        int128 y = ABDKMath64x64.fromInt(2);
        ABDKMath64x64.mul(x, y);
    }
}
