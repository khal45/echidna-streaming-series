// pragma solidity ^0.6.0;

// import "../uni-v2/UniswapV2Pair.sol";
// import "../uni-v2/UniswapV2ERC20.sol";
// import "../uni-v2/UniswapV2Factory.sol";
// import "../libraries/UniswapV2Library.sol";
// import "../uni-v2/UniswapV2Router01.sol";

// contract Users {
//     function proxy(address target, bytes memory _calldata) public returns (bool success, bytes memory returnData) {
//         (success, returnData) = address(target).call(_calldata);
//     }
// }

// contract UniswapV2Test {
//     UniswapV2ERC20 token0;
//     UniswapV2ERC20 token1;
//     UniswapV2Pair testPair;
//     UniswapV2Factory factory;
//     UniswapV2Router01 router;
//     Users user;
//     bool complete;

//     constructor() public {
//         token0 = new UniswapV2ERC20();
//         token1 = new UniswapV2ERC20();
//         factory = new UniswapV2Factory(address(this)); //this contract will be the fee setter
//         router = new UniswapV2Router01(address(factory), address(0)); // we don't need to test WETH pairs for now
//         address pair = factory.createPair(address(token0), address(token1));
//         testPair = UniswapV2Pair(pair);
//         user = new Users();
//         // Sort the test tokens we just created, for clarity when writing invariant tests later
//         (address testTokenA, address testTokenB) = UniswapV2Library.sortTokens(address(token0), address(token1));
//         token0 = UniswapV2ERC20(testTokenA);
//         token1 = UniswapV2ERC20(testTokenB);
//     }
//     uint256 ghostDeposited0;
//     uint256 ghostDeposited1;
//     uint256 ghostWithdrawn0;
//     uint256 ghostWithdrawn1;

//     function addLiquidity(uint256 amount0, uint256 amount1)
//         public
//         returns (bool success, uint256 amountA, uint256 amountB, uint256 liquidity)
//     {
//         amount0 = _between(amount0, 1001, uint112(-1));
//         amount1 = _between(amount1, 1001, uint112(-1));

//         _init(amount0, amount1);
//         uint256 balance0 = token0.balanceOf(address(user));
//         uint256 balance1 = token1.balanceOf(address(user));
//         bytes memory returnData;
//         (success, returnData) = user.proxy(
//             address(router),
//             abi.encodeWithSelector(
//                 router.addLiquidity.selector,
//                 address(token0),
//                 address(token1),
//                 amount0,
//                 amount1,
//                 0,
//                 0,
//                 address(user),
//                 uint256(-1)
//             )
//         );
//         if (success) {
//             (amountA, amountB, liquidity) = abi.decode(returnData, (uint256, uint256, uint256));
//             ghostDeposited0 += balance0 - token0.balanceOf(address(user));
//             ghostDeposited1 += balance1 - token1.balanceOf(address(user));
//         }
//     }

//     function removeLiquidity(uint256 liquidity) public returns (bool success, uint256 amountA, uint256 amountB) {
//         uint256 userLiquidity = testPair.balanceOf(address(user));
//         if (userLiquidity == 0) {
//             return (false, 0, 0);
//         }
//         liquidity = _between(liquidity, 1, userLiquidity);

//         _doApprovals();
//         uint256 balance0 = token0.balanceOf(address(user));
//         uint256 balance1 = token1.balanceOf(address(user));

//         bytes memory returnData;
//         (success, returnData) = user.proxy(
//             address(router),
//             abi.encodeWithSelector(
//                 router.removeLiquidity.selector,
//                 address(token0),
//                 address(token1),
//                 liquidity,
//                 0,
//                 0,
//                 address(user),
//                 uint256(-1)
//             )
//         );
//         if (success) {
//             (amountA, amountB) = abi.decode(returnData, (uint256, uint256));
//             ghostWithdrawn0 += token0.balanceOf(address(user)) - balance0;
//             ghostWithdrawn1 += token1.balanceOf(address(user)) - balance1;
//         }
//     }

//     function _getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
//         return UniswapV2Library.getReserves(address(factory), tokenA, tokenB);
//     }

//     function _doApprovals() internal {
//         user.proxy(address(token0), abi.encodeWithSelector(token0.approve.selector, address(router), uint256(-1)));
//         user.proxy(address(token1), abi.encodeWithSelector(token1.approve.selector, address(router), uint256(-1)));
//         user.proxy(address(testPair), abi.encodeWithSelector(testPair.approve.selector, address(router), uint256(-1)));
//     }

//     function _init(uint256 amount0, uint256 amount1) internal {
//         token0.mint(address(user), amount0);
//         token1.mint(address(user), amount1);
//         _doApprovals();
//         // complete = true;
//     }

//     function _between(uint256 val, uint256 lower, uint256 upper) internal pure returns (uint256) {
//         return lower + (val % (upper - lower + 1));
//     }

//     // echidna tests
//     // what is the first system level invariant you want to test?
//     // after a burn, lp token0 and token1 should not increase by more than expected amount0 and amount1
//     function echidna_lp_never_withdraws_more_than_deposited() public view returns (bool) {
//         return ghostWithdrawn0 <= ghostDeposited0 && ghostWithdrawn1 <= ghostDeposited1;
//     }
// }
