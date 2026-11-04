pragma solidity ^0.6.0;

contract Users {
    function proxy(address target, bytes memory _calldata)
        public
        payable
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = address(target).call{value: msg.value}(_calldata);
    }

    receive() external payable {}
}
