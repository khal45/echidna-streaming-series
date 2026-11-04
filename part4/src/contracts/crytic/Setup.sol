pragma solidity ^0.6.0;

import "../uni-v2/UniswapV2Pair.sol";
import "../uni-v2/UniswapV2ERC20.sol";
import "../uni-v2/UniswapV2Factory.sol";
import "../libraries/UniswapV2Library.sol";
import "../uni-v2/UniswapV2Router01.sol";
import "./MockWETH.sol";
import "./Users.sol";

abstract contract Setup {
    UniswapV2ERC20 internal token0;
    UniswapV2ERC20 internal token1;
    UniswapV2Pair internal testPair;
    UniswapV2Factory internal factory;
    UniswapV2Router01 internal router;
    MockWETH internal weth;
    Users internal user;

    constructor() public {
        token0 = new UniswapV2ERC20();
        token1 = new UniswapV2ERC20();
        factory = new UniswapV2Factory(address(this)); // this contract is the fee setter
        weth = new MockWETH(); // mock WETH added for the ETH router wrappers
        router = new UniswapV2Router01(address(factory), address(weth));
        address pair = factory.createPair(address(token0), address(token1));
        testPair = UniswapV2Pair(pair);
        user = new Users();

        // Sort tokens so token0/token1 match the pair's ordering
        (address testTokenA, address testTokenB) = UniswapV2Library.sortTokens(address(token0), address(token1));
        token0 = UniswapV2ERC20(testTokenA);
        token1 = UniswapV2ERC20(testTokenB);
    }

    function _getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        return UniswapV2Library.getReserves(address(factory), tokenA, tokenB);
    }

    function _doApprovals() internal {
        user.proxy(address(token0), abi.encodeWithSelector(token0.approve.selector, address(router), uint256(-1)));
        user.proxy(address(token1), abi.encodeWithSelector(token1.approve.selector, address(router), uint256(-1)));
        user.proxy(address(testPair), abi.encodeWithSelector(testPair.approve.selector, address(router), uint256(-1)));
        address ethPair = UniswapV2Library.pairFor(address(factory), address(token0), address(weth));
        user.proxy(ethPair, abi.encodeWithSelector(testPair.approve.selector, address(router), uint256(-1)));
    }

    function _init(uint256 amount0, uint256 amount1) internal {
        token0.mint(address(user), amount0);
        token1.mint(address(user), amount1);
        _doApprovals();
    }

    function _between(uint256 val, uint256 lower, uint256 upper) internal pure returns (uint256) {
        require(upper >= lower, "Invalid bounds");
        return lower + (val % (upper - lower + 1));
    }
}
