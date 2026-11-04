pragma solidity ^0.6.0;

// Let's think about what needs to be in the setup contract
// a setup contract is basically a contract that contains the setup for an echidna test
// let's start with something we want to test and see what setup would be needed
// invariant: minting tokens increases k

// what do we need to mint tokens?:
// we need an account that'll mint the tokens
// we'll need some helper functions. We'll come back to those functions later
// we'll need to deploy the pair and other contracts that'll be needed
import {UniswapV2Pair} from "../uni-v2/UniswapV2Pair.sol";
import {UniswapV2ERC20} from "../uni-v2/UniswapV2ERC20.sol";
import {UniswapV2Factory} from "../uni-v2/UniswapV2Factory.sol";

contract Users {
    function proxy(address target, bytes memory data) public returns (bool success, bytes memory returnData) {
        return target.call(data);
    }
}

contract Setup {
    UniswapV2Pair pair;
    UniswapV2ERC20 token0;
    UniswapV2ERC20 token1;
    UniswapV2Factory factory;
    Users user;
    bool completed;

    // tokens that were donated to the pair without being minted (and that would
    // overflow the pair's uint112 reserves) are pushed here when we normalize
    address internal constant SKIM_SINK = 0x000000000000000000000000000000000000dEaD;

    // selectors for the pair functions we drive through the low level `user.proxy`
    bytes4 internal constant MINT_SELECTOR = bytes4(keccak256("mint(address)"));
    bytes4 internal constant BURN_SELECTOR = bytes4(keccak256("burn(address)"));
    bytes4 internal constant SYNC_SELECTOR = bytes4(keccak256("sync()"));
    bytes4 internal constant SKIM_SELECTOR = bytes4(keccak256("skim(address)"));
    bytes4 internal constant PAIR_TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    constructor() public {
        token0 = new UniswapV2ERC20();
        token1 = new UniswapV2ERC20();
        factory = new UniswapV2Factory(address(this));
        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = UniswapV2Pair(pairAddress);
        user = new Users();
    }

    // what are the helper functions we'll need?
    function _mintTokens(uint256 amount1, uint256 amount2) internal {
        token0.mint(address(user), amount1);
        token1.mint(address(user), amount2);
        completed = true;
    }

    function _between(uint256 val, uint256 low, uint256 high) internal pure returns (uint256) {
        return low + (val % (high - low + 1));
    }

    // --- helpers for the burn() invariants -------------------------------------
    // the mint/burn/skim/sync calls below always go through `user.proxy` so that
    // a reverting call is observable (success flag) instead of reverting the test

    // make sure `user` can afford a deposit of the given size
    function _fund(uint256 amount0, uint256 amount1) internal {
        if (token0.balanceOf(address(user)) < amount0) {
            token0.mint(address(user), amount0);
        }
        if (token1.balanceOf(address(user)) < amount1) {
            token1.mint(address(user), amount1);
        }
    }

    // deposit both tokens into the pair and mint the LP tokens to `user`
    function _deposit(uint256 amount0, uint256 amount1) internal returns (bool success) {
        _fund(amount0, amount1);
        (bool ok0,) =
            user.proxy(address(token0), abi.encodeWithSelector(token0.transfer.selector, address(pair), amount0));
        (bool ok1,) =
            user.proxy(address(token1), abi.encodeWithSelector(token1.transfer.selector, address(pair), amount1));
        if (!(ok0 && ok1)) return false;
        (bool ok2,) = user.proxy(address(pair), abi.encodeWithSelector(MINT_SELECTOR, address(user)));
        return ok2;
    }

    // get the pair into a state where `user` holds LP tokens that can be burned:
    //  - empty pair: bootstrap it (needs sqrt(amount0 * amount1) > MINIMUM_LIQUIDITY,
    //    so the caller must pass amounts around the size used in the test bounds)
    //  - pair without a position for `user`: deposit a quarter of the reserves so
    //    the mint is guaranteed to issue some LP tokens
    function _ensureLiquidity(uint256 amount0, uint256 amount1) internal returns (bool) {
        if (pair.totalSupply() > 0 && pair.balanceOf(address(user)) > 0) return true;
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        return _deposit(uint256(reserve0) / 4 + amount0, uint256(reserve1) / 4 + amount1);
    }

    // hand LP tokens to the pair so that `burn` has something to destroy
    function _sendLiquidityToPair(uint256 liquidity) internal returns (bool) {
        if (pair.balanceOf(address(user)) < liquidity) return false;
        (bool ok,) = user.proxy(address(pair), abi.encodeWithSelector(PAIR_TRANSFER_SELECTOR, address(pair), liquidity));
        return ok;
    }

    // bring the reserves back in line with the pair's real token balances (earlier
    // calls may have donated tokens to the pair without minting), so that
    // k = reserve0 * reserve1 is meaningful before a burn
    function _sync() internal returns (bool) {
        (bool ok,) = user.proxy(address(pair), abi.encodeWithSelector(SYNC_SELECTOR));
        if (ok) return true;
        // balances overflow the uint112 reserves: skim the excess away, then retry
        (bool okSkim,) = user.proxy(address(pair), abi.encodeWithSelector(SKIM_SELECTOR, SKIM_SINK));
        if (!okSkim) return false;
        (ok,) = user.proxy(address(pair), abi.encodeWithSelector(SYNC_SELECTOR));
        return ok;
    }

    // low level burn so the tests can observe success/failure and the returned amounts
    function _burnLiquidity(address to) internal returns (bool success, uint256 amount0, uint256 amount1) {
        (bool ok, bytes memory returnData) = user.proxy(address(pair), abi.encodeWithSelector(BURN_SELECTOR, to));
        if (ok && returnData.length >= 64) {
            (amount0, amount1) = abi.decode(returnData, (uint256, uint256));
        }
        return (ok, amount0, amount1);
    }
}
