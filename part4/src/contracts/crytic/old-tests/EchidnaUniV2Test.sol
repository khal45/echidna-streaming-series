// pragma solidity ^0.6.0;
// import "./Harness.sol";
// import "../libraries/UniswapV2Library.sol";

// contract EchidnaUniV2Test is Setup {
//     using SafeMath for uint256;
//     event logUints(uint256 kBefore, uint256 kAfter);

//     function testProvideLiquidityInvariants(uint256 amount0, uint256 amount1) public {
//         //PRECONDITIONS:
//         amount0 = _between(amount0, 1000, uint256(-1));
//         amount1 = _between(amount1, 1000, uint256(-1));
//         if (!complete) {
//             _init(amount0, amount1);
//         }

//         uint256 pairBalanceBefore = testPair.balanceOf(address(user));

//         (uint256 reserve1Before, uint256 reserve2Before) = _getReserves(address(testToken1), address(testToken2));

//         emit logUints(reserve1Before, reserve2Before);
//         uint256 kBefore = reserve1Before * reserve2Before;

//         //CALL:

//         (bool success,) = user.proxy(
//             address(router),
//             abi.encodeWithSelector(
//                 router.addLiquidity.selector,
//                 address(testToken1),
//                 address(testToken2),
//                 amount0,
//                 amount1,
//                 0,
//                 0,
//                 address(user),
//                 uint256(-1)
//             )
//         );

//         //POSTCONDITIONS

//         if (success) {
//             (uint256 reserve1After, uint256 reserve2After) = _getReserves(address(testToken1), address(testToken2));
//             uint256 pairBalanceAfter = testPair.balanceOf(address(user));
//             uint256 kAfter = reserve1After * reserve2After;
//             assert(kBefore < kAfter);
//             assert(pairBalanceBefore < pairBalanceAfter);
//         }
//     }

//     function testFirstProvideLiquidityIncreasesK(uint256 amount0, uint256 amount1) public {
//         //PRECONDITIONS:
//         amount0 = _between(amount0, 1001, uint256(-1));
//         amount1 = _between(amount1, 1001, uint256(-1));

//         (uint256 reserve1Before, uint256 reserve2Before) = _getReserves(address(testToken1), address(testToken2));
//         // only test the very first liquidity provision, when reserves are still empty
//         require(reserve1Before == 0 && reserve2Before == 0);

//         _init(amount0, amount1);

//         uint256 kBefore = reserve1Before * reserve2Before;

//         //CALL:
//         (bool success,) = user.proxy(
//             address(router),
//             abi.encodeWithSelector(
//                 router.addLiquidity.selector,
//                 address(testToken1),
//                 address(testToken2),
//                 amount0,
//                 amount1,
//                 0,
//                 0,
//                 address(user),
//                 uint256(-1)
//             )
//         );

//         //POSTCONDITIONS

//         if (success) {
//             (uint256 reserve1After, uint256 reserve2After) = _getReserves(address(testToken1), address(testToken2));
//             uint256 kAfter = reserve1After * reserve2After;
//             emit logUints(kBefore, kAfter);
//             assert(kAfter > kBefore);
//         }
//     }

//     function testCannotSwapZeroTokens(uint256 amount0, uint256 amount1) public {
//         // preconditions
//         _prepareSwap(amount0, amount1);
//         // actions
//         (bool success1,) = user.proxy(
//             address(testPair), abi.encodeWithSelector(testPair.swap.selector, amount0, amount1, address(user), "")
//         );
//         // postconditions
//         assert(!success1);
//     }

//     function testSwapChangesBalancesAppropriately(uint256 amount0, uint256 amount1) public {
//         // preconditions
//         _prepareSwap(amount0, amount1);

//         address token0 = testPair.token0();
//         address token1 = testPair.token1();

//         // bound input to what the user actually owns
//         uint256 userBal0 = IERC20(token0).balanceOf(address(user));
//         require(userBal0 > 0);
//         amount0 = _between(amount0, 1, userBal0);

//         (uint256 reserve0Before, uint256 reserve1Before) = _getReserves(token0, token1);
//         uint256 kBefore = reserve0Before * reserve1Before;
//         uint256 expectedAmountOut = UniswapV2Library.getAmountOut(amount0, reserve0Before, reserve1Before);

//         uint256 token1Before = IERC20(token1).balanceOf(address(user));
//         uint256 token0Before = IERC20(token0).balanceOf(address(user));

//         // actions
//         bool success = _swap(token0, token1, amount0);

//         // postconditions
//         if (success) {
//             _checkSwapBalances(token0, token1, amount0, expectedAmountOut, token0Before, token1Before);

//             (uint256 reserve0After, uint256 reserve1After) = _getReserves(token0, token1);
//             uint256 kAfter = reserve0After * reserve1After;
//             assert(kAfter > kBefore);
//         }
//     }

//     function testSwapBothDirectionsChangesBalances(uint256 amount0, uint256 amount1) public {
//         // preconditions
//         _prepareSwap(amount0, amount1);

//         address token0 = testPair.token0();
//         address token1 = testPair.token1();

//         // leg 1: token0 -> token1
//         _swapAndCheck(token0, token1, amount0);

//         // leg 2: token1 -> token0 (reserves have changed, helper re-reads them)
//         _swapAndCheck(token1, token0, amount1);
//     }

//     function _swapAndCheck(address tokenIn, address tokenOut, uint256 amountIn) internal {
//         uint256 userBalIn = IERC20(tokenIn).balanceOf(address(user));
//         if (userBalIn == 0) return;

//         // bound to the user's balance and to uint112 so getAmountOut can't overflow
//         uint256 maxIn = userBalIn < uint112(-1) ? userBalIn : uint112(-1);
//         amountIn = _between(amountIn, 1, maxIn);

//         address[] memory path = new address[](2);
//         path[0] = tokenIn;
//         path[1] = tokenOut;

//         (uint256 reserve0Before, uint256 reserve1Before) = _getReserves(tokenIn, tokenOut);
//         uint256 expectedOut = UniswapV2Library.getAmountOut(amountIn, reserve0Before, reserve1Before);

//         uint256 inBefore = IERC20(tokenIn).balanceOf(address(user));
//         uint256 outBefore = IERC20(tokenOut).balanceOf(address(user));

//         // action: call as the user
//         (bool success,) = user.proxy(
//             address(router),
//             abi.encodeWithSelector(
//                 router.swapExactTokensForTokens.selector, amountIn, 0, path, address(user), uint256(-1)
//             )
//         );

//         // postconditions
//         if (success) {
//             assert(IERC20(tokenIn).balanceOf(address(user)) == inBefore - amountIn);
//             assert(IERC20(tokenOut).balanceOf(address(user)) == outBefore + expectedOut);
//         }
//     }

//     function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (bool success) {
//         address[] memory path = new address[](2);
//         path[0] = tokenIn;
//         path[1] = tokenOut;

//         (success,) = user.proxy(
//             address(router),
//             abi.encodeWithSelector(
//                 router.swapExactTokensForTokens.selector, amountIn, 0, path, address(user), uint256(-1)
//             )
//         );
//     }

//     function _getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
//         return UniswapV2Library.getReserves(address(factory), tokenA, tokenB);
//     }

//     function _checkSwapBalances(
//         address token0,
//         address token1,
//         uint256 amount0,
//         uint256 expectedAmountOut,
//         uint256 token0Before,
//         uint256 token1Before
//     ) internal view {
//         assert(IERC20(token1).balanceOf(address(user)) >= token1Before + expectedAmountOut);
//         assert(IERC20(token0).balanceOf(address(user)) <= token0Before - amount0);
//     }

//     function _prepareSwap(uint256 amount0, uint256 amount1) internal {
//         if (!complete) {
//             _init(amount0, amount1);
//         }
//         require(testPair.balanceOf(address(user)) > 0); // ensures there's liquidity
//         testPair.sync(); // match the balance with the reserves
//     }
// }
