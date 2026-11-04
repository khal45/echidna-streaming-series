// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {IUniswapV2Factory} from "../src/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../src/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2ERC20} from "../src/contracts/interfaces/IUniswapV2ERC20.sol";
import {IUniswapV2Router01} from "../src/contracts/interfaces/IUniswapV2Router01.sol";

interface ITestERC20 is IUniswapV2ERC20 {
    function mint(address to, uint256 amount) external;
}

abstract contract BaseTest is Test {
    IUniswapV2Factory internal factory;
    IUniswapV2Router01 internal router;
    IUniswapV2Pair internal pair;

    ITestERC20 internal token0;
    ITestERC20 internal token1;

    address internal feeToSetter = makeAddr("feeToSetter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal weth = makeAddr("weth");

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public virtual {
        factory = IUniswapV2Factory(deployCode("UniswapV2Factory.sol:UniswapV2Factory", abi.encode(feeToSetter)));

        router = IUniswapV2Router01(
            deployCode("UniswapV2Router01.sol:UniswapV2Router01", abi.encode(address(factory), weth))
        );

        ITestERC20 tokenA = ITestERC20(deployCode("UniswapV2ERC20.sol:UniswapV2ERC20"));

        ITestERC20 tokenB = ITestERC20(deployCode("UniswapV2ERC20.sol:UniswapV2ERC20"));

        pair = IUniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));

        // Read the sorted token addresses from the pair.
        token0 = ITestERC20(pair.token0());
        token1 = ITestERC20(pair.token1());

        // Fund test actors.
        token0.mint(alice, 1_000_000e18);
        token1.mint(alice, 1_000_000e18);

        token0.mint(bob, 1_000_000e18);
        token1.mint(bob, 1_000_000e18);
    }

    // Direct pair liquidity provision (without Router).
    function _addLiquidityDirect(address lp, uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        vm.startPrank(lp);

        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);

        liquidity = pair.mint(lp);

        vm.stopPrank();
    }

    function _addLiquidity(address lp, uint256 amount0, uint256 amount1)
        internal
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        vm.startPrank(lp);

        token0.approve(address(router), amount0);
        token1.approve(address(router), amount1);

        (amountA, amountB, liquidity) = router.addLiquidity(
            address(token0), address(token1), amount0, amount1, 0, 0, alice, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function _removeLiquidity(
        address lp,
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) internal returns (uint256 amountA, uint256 amountB) {
        vm.startPrank(lp);

        pair.approve(address(router), liquidity);

        (amountA, amountB) = router.removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);

        vm.stopPrank();
    }
}
