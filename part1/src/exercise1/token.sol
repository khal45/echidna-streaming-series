pragma solidity ^0.7.0;

contract Ownership {
    address owner = msg.sender;

    function Owner() public {
        owner = msg.sender;
    }

    modifier isOwner() {
        require(owner == msg.sender);
        _;
    }
}

contract Pausable is Ownership {
    bool is_paused;

    modifier ifNotPaused() {
        require(!is_paused);
        _;
    }

    function paused() public isOwner {
        is_paused = true;
    }

    function resume() public isOwner {
        is_paused = false;
    }
}

contract Token is Pausable {
    mapping(address => uint256) public balances;

    function transfer(address to, uint256 value) public ifNotPaused {
        // @audit this is a regular transfer function that updates balances
        // we are prolly missing some checks here
        // this can underflow because we are using a solidity version less than 0.8.0
        balances[msg.sender] -= value;
        balances[to] += value;
    }
}
