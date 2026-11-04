pragma solidity ^0.6.0;

import "./wrapper.sol";
import "../libraries/Math.sol";

contract UniswapV2AssertionTest is Wrapper {
    event debugK(uint256 kBefore, uint256 KAfter);
    event debugLpAmount0(uint256 lpAmount0Before, uint256 lpAmount0After);
    event debugLpAmount1(uint256 lpAmount1Before, uint256 lpAmount1After);
    event debugLpBalance(uint256 lpBalanceBefore, uint256 lpBalanceAfter);

    function testProvideLiquidityInvariants(uint256 amount0, uint256 amount1) public {
        // preconditions
        (uint256 reserve0Before, uint256 reserve1Before) = _getReserves(address(token0), address(token1));
        uint256 kBefore = reserve0Before * reserve1Before;
        uint256 lpBefore = testPair.balanceOf(address(user));
        uint256 ghost0Before = ghostDeposited0;
        uint256 ghost1Before = ghostDeposited1;

        // actions
        (bool success, uint256 amountA, uint256 amountB, uint256 liquidity) = addLiquidity(amount0, amount1);
        if (!success) return; // legit reverts (overflow, insufficient liquidity) are not violations

        (uint256 reserve0After, uint256 reserve1After) = _getReserves(address(token0), address(token1));
        uint256 kAfter = reserve0After * reserve1After;
        uint256 lpAfter = testPair.balanceOf(address(user));

        emit debugK(kBefore, kAfter);
        emit debugLpBalance(lpBefore, lpAfter);

        // post conditions
        // k strictly increases
        assert(kAfter > kBefore);
        // reserves grew by exactly what the router reported
        assert(reserve0After == reserve0Before + amountA);
        assert(reserve1After == reserve1Before + amountB);
        // user paid exactly amountA/amountB (ghost accounting)
        assert(ghostDeposited0 - ghost0Before == amountA);
        assert(ghostDeposited1 - ghost1Before == amountB);
        // LP tokens received
        assert(lpAfter == lpBefore + liquidity);
        assert(lpAfter > lpBefore);
    }

    // first liquidity provision mints LP tokens equal to sqrt(amount0 * amount1),
    // minus the MINIMUM_LIQUIDITY permanently locked to address(0)
    function testInitialLiquidityIsSqrtOfAmounts(uint256 amount0, uint256 amount1) public {
        amount0 = _between(amount0, 1001, uint112(-1));
        amount1 = _between(amount1, 1001, uint112(-1));

        // fresh tokens + pair so reserves start at zero on every call
        UniswapV2ERC20 freshToken0 = new UniswapV2ERC20();
        UniswapV2ERC20 freshToken1 = new UniswapV2ERC20();
        UniswapV2Pair freshPair = UniswapV2Pair(factory.createPair(address(freshToken0), address(freshToken1)));

        freshToken0.mint(address(user), amount0);
        freshToken1.mint(address(user), amount1);

        user.proxy(
            address(freshToken0), abi.encodeWithSelector(freshToken0.approve.selector, address(router), uint256(-1))
        );
        user.proxy(
            address(freshToken1), abi.encodeWithSelector(freshToken1.approve.selector, address(router), uint256(-1))
        );

        (bool success, bytes memory returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.addLiquidity.selector,
                address(freshToken0),
                address(freshToken1),
                amount0,
                amount1,
                0,
                0,
                address(user),
                uint256(-1)
            )
        );
        if (!success) return; // legit reverts are not violations

        (,, uint256 liquidity) = abi.decode(returnData, (uint256, uint256, uint256));
        uint256 expectedSupply = Math.sqrt(amount0 * amount1);
        uint256 minimumLiquidity = freshPair.MINIMUM_LIQUIDITY();

        // user receives sqrt(k) - MINIMUM_LIQUIDITY, total supply is sqrt(k)
        assert(liquidity == expectedSupply - minimumLiquidity);
        assert(freshPair.balanceOf(address(user)) == liquidity);
        assert(freshPair.totalSupply() == expectedSupply);
        // the minimum liquidity is locked forever
        assert(freshPair.balanceOf(address(0)) == minimumLiquidity);
    }

    // subsequent liquidity is minted proportionally to the pool share added:
    // liquidity = amount * totalSupply / reserve (for both tokens)
    function testSubsequentLiquidityIsProportionalToPoolShare(uint256 seed0, uint256 seed1, uint256 multiplier) public {
        seed0 = _between(seed0, 1001, 1e6);
        seed1 = _between(seed1, 1001, 1e6);

        // fresh tokens + pair so the first mint is deterministic
        (UniswapV2ERC20 freshToken0, UniswapV2ERC20 freshToken1, UniswapV2Pair freshPair) = _createFreshPool();
        _approveFreshTokens(freshToken0, freshToken1);

        freshToken0.mint(address(user), seed0);
        freshToken1.mint(address(user), seed1);
        {
            (bool seeded,,,) = _addFreshLiquidity(freshToken0, freshToken1, seed0, seed1);
            if (!seeded) return;
        }

        uint256 totalSupplyBefore = freshPair.totalSupply();
        // deposit an exact multiple of the reserves so both min() terms are equal
        multiplier = _between(multiplier, 1, uint112(-1) / (seed0 > seed1 ? seed0 : seed1));
        uint256 amount0 = seed0 * multiplier;
        uint256 amount1 = seed1 * multiplier;

        freshToken0.mint(address(user), amount0);
        freshToken1.mint(address(user), amount1);

        (bool success,,, uint256 liquidity) = _addFreshLiquidity(freshToken0, freshToken1, amount0, amount1);
        if (!success) return; // legit reverts are not violations

        uint256 expectedLiquidity = multiplier * totalSupplyBefore;

        // liquidity is exactly the share of the pool being added
        assert(liquidity == expectedLiquidity);
        assert(liquidity * seed0 == amount0 * totalSupplyBefore);
        assert(liquidity * seed1 == amount1 * totalSupplyBefore);
        assert(freshPair.totalSupply() == totalSupplyBefore + expectedLiquidity);
    }

    // providing then removing the same liquidity should return the deposited
    // amounts minus rounding (Uniswap V2 charges no fee for mint/burn)
    function testProvideRemoveLiquidityRoundTrip(uint256 seed0, uint256 seed1, uint256 amount0, uint256 amount1)
        public
    {
        seed0 = _between(seed0, 1e6, 1e9);
        seed1 = _between(seed1, 1e6, 1e9);

        // a separate LP seeds the pool so the locked MINIMUM_LIQUIDITY does not
        // eat into the user's round trip
        (UniswapV2ERC20 freshToken0, UniswapV2ERC20 freshToken1, UniswapV2Pair freshPair) = _createFreshPool();
        _seedFreshPool(freshToken0, freshToken1, freshPair, seed0, seed1);
        _approveFreshTokens(freshToken0, freshToken1);
        user.proxy(address(freshPair), abi.encodeWithSelector(freshPair.approve.selector, address(router), uint256(-1)));

        amount0 = _between(amount0, 1, seed0);
        amount1 = _between(amount1, 1, seed1);
        freshToken0.mint(address(user), amount0);
        freshToken1.mint(address(user), amount1);

        _assertLiquidityRoundTrip(freshToken0, freshToken1, amount0, amount1, seed0, seed1);
    }

    function _assertLiquidityRoundTrip(
        UniswapV2ERC20 freshToken0,
        UniswapV2ERC20 freshToken1,
        uint256 amount0,
        uint256 amount1,
        uint256 seed0,
        uint256 seed1
    ) internal {
        (bool added, uint256 deposited0, uint256 deposited1, uint256 liquidity) =
            _addFreshLiquidity(freshToken0, freshToken1, amount0, amount1);
        if (!added) return; // legit reverts are not violations

        (bool removed, uint256 returned0, uint256 returned1) =
            _removeFreshLiquidity(freshToken0, freshToken1, liquidity);
        if (!removed) return;

        // 1. never profit: rounding always favors the pool
        assert(returned0 <= deposited0);
        assert(returned1 <= deposited1);

        // 2. loss bounded by the marginal price plus the LP rounding dust,
        //    same tolerance style as testSwapRoundTripPathIndependence
        uint256 rootK = Math.sqrt(seed0 * seed1);
        assert(returned0 + (seed0 + deposited0) / seed1 + (seed0 + deposited0) / rootK + 2 >= deposited0);
        assert(returned1 + (seed1 + deposited1) / seed0 + (seed1 + deposited1) / rootK + 2 >= deposited1);
    }

    function _createFreshPool()
        internal
        returns (UniswapV2ERC20 freshToken0, UniswapV2ERC20 freshToken1, UniswapV2Pair freshPair)
    {
        freshToken0 = new UniswapV2ERC20();
        freshToken1 = new UniswapV2ERC20();
        freshPair = UniswapV2Pair(factory.createPair(address(freshToken0), address(freshToken1)));
    }

    function _approveFreshTokens(UniswapV2ERC20 freshToken0, UniswapV2ERC20 freshToken1) internal {
        user.proxy(
            address(freshToken0), abi.encodeWithSelector(freshToken0.approve.selector, address(router), uint256(-1))
        );
        user.proxy(
            address(freshToken1), abi.encodeWithSelector(freshToken1.approve.selector, address(router), uint256(-1))
        );
    }

    function _addFreshLiquidity(
        UniswapV2ERC20 freshToken0,
        UniswapV2ERC20 freshToken1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (bool success, uint256 deposited0, uint256 deposited1, uint256 liquidity) {
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.addLiquidity.selector,
                address(freshToken0),
                address(freshToken1),
                amount0,
                amount1,
                0,
                0,
                address(user),
                uint256(-1)
            )
        );
        if (success) {
            (deposited0, deposited1, liquidity) = abi.decode(returnData, (uint256, uint256, uint256));
        }
    }

    function _seedFreshPool(
        UniswapV2ERC20 freshToken0,
        UniswapV2ERC20 freshToken1,
        UniswapV2Pair freshPair,
        uint256 amount0,
        uint256 amount1
    ) internal {
        freshToken0.mint(address(this), amount0);
        freshToken1.mint(address(this), amount1);
        freshToken0.transfer(address(freshPair), amount0);
        freshToken1.transfer(address(freshPair), amount1);
        freshPair.mint(address(this));
    }

    function _removeFreshLiquidity(UniswapV2ERC20 freshToken0, UniswapV2ERC20 freshToken1, uint256 liquidity)
        internal
        returns (bool success, uint256 amount0, uint256 amount1)
    {
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.removeLiquidity.selector,
                address(freshToken0),
                address(freshToken1),
                liquidity,
                0,
                0,
                address(user),
                uint256(-1)
            )
        );
        if (success) {
            (amount0, amount1) = abi.decode(returnData, (uint256, uint256));
        }
    }

    // pool invariants must stay constant during swaps
    // @note this doesn't handle multi hop swap for now
    function testKNeverDecreasesDuringSwaps(uint256 amount0, uint256 amount1) public {
        // preconditions
        // what do I need to do to setup the test?
        uint256 userBalance0 = IERC20(address(token0)).balanceOf(address(user));
        uint256 userBalance1 = IERC20(address(token1)).balanceOf(address(user));

        // bound amount0 and amount1 to how much the user has
        amount0 = _between(amount0, 1001, userBalance0);
        amount1 = _between(amount1, 1001, userBalance1);

        // ensure there's liquidity
        (bool success1,,,) = addLiquidity(amount0, amount1);
        if (!success1) return; // legit reverts are not violations
        // get k before swaps
        (uint256 reserve0Before, uint256 reserve1Before) = _getReserves(address(token0), address(token1));
        uint256 kBefore = reserve0Before * reserve1Before;
        // create path array
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        // actions
        (bool success,) = swapExactTokensForTokens(userBalance0, 0, path);
        // post conditions
        if (success) {
            (uint256 reserve0After, uint256 reserve1After) = _getReserves(address(token0), address(token1));
            uint256 kAfter = reserve0After * reserve1After;
            assert(kAfter >= kBefore);
        }
    }

    // after a swap the user must receive exactly the output amount the router
    // quoted, and the pool must release exactly that same amount
    function testSwapDeliversIntendedOutputAndDecreasesPool(uint256 amount0, uint256 amount1) public {
        // preconditions
        uint256 userBalance0 = token0.balanceOf(address(user));
        uint256 userBalance1 = token1.balanceOf(address(user));

        // bound amount0 and amount1 to how much the user has
        amount0 = _between(amount0, 1001, userBalance0);
        amount1 = _between(amount1, 1001, userBalance1);

        // ensure there's liquidity
        (bool success1,,,) = addLiquidity(amount0, amount1);
        if (!success1) return; // legit reverts are not violations

        // reserves and pool/user balances before the swap
        (uint256 reserve0Before, uint256 reserve1Before) = _getReserves(address(token0), address(token1));
        uint256 poolBalance1Before = token1.balanceOf(address(testPair));
        uint256 userBalance1Before = token1.balanceOf(address(user));

        // create path array
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        // actions
        (bool success, uint256[] memory amounts) = swapExactTokensForTokens(userBalance0, 0, path);
        if (!success) return; // legit reverts are not violations

        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        // the returned output is exactly what the router quoted for this input
        uint256 intendedOut = router.getAmountOut(amountIn, reserve0Before, reserve1Before);
        assert(amountOut == intendedOut);

        // the user actually received the intended output
        assert(token1.balanceOf(address(user)) == userBalance1Before + amountOut);

        // the pool released exactly the amount sent to the user
        assert(token1.balanceOf(address(testPair)) == poolBalance1Before - amountOut);

        // the input reserve grew by exactly the amount sent in
        (uint256 reserve0After,) = _getReserves(address(token0), address(token1));
        assert(reserve0After == reserve0Before + amountIn);
    }

    function testKNeverDecreasesDuringDirectSwaps(uint256 amountIn, uint256 liquidity0, uint256 liquidity1) public {
        (uint256 reserve0, uint256 reserve1) = _getReserves(address(token0), address(token1));

        // seed the pool on first call
        _seedPool(reserve0, reserve1, liquidity0, liquidity1);

        amountIn = _between(amountIn, 1, reserve0 - 1);
        token0.mint(address(user), amountIn); // guarantee funds

        uint256 kBefore = reserve0 * reserve1;
        (bool success,) = directSwapExactTokensForTokens(amountIn);
        if (!success) return;

        (uint256 reserve0After, uint256 reserve1After) = _getReserves(address(token0), address(token1));
        emit debugK(kBefore, reserve0After * reserve1After);
        assert(reserve0After * reserve1After >= kBefore);
    }

    function testZeroInputSwapReverts(uint256 amount0Out, uint256 amount1Out, uint256 liquidity0, uint256 liquidity1)
        public
    {
        (uint256 reserve0, uint256 reserve1) = _getReserves(address(token0), address(token1));

        // seed the pool on first call
        _seedPool(reserve0, reserve1, liquidity0, liquidity1);

        // skip if the pair holds surplus tokens: swap() counts balance > reserve as input
        // @note if balance ≠ reserve for either token, the pair already holds hidden input, so “zero input” isn’t actually zero. The test returns early and skips that case.
        if (token0.balanceOf(address(testPair)) != reserve0 || token1.balanceOf(address(testPair)) != reserve1) return;

        // 0 allowed (covers swap(0,0)); capped below reserves
        amount0Out = amount0Out % reserve0;
        amount1Out = amount1Out % reserve1;

        // swap directly on the pair with no tokens transferred in

        (bool success,) = user.proxy(
            address(testPair),
            abi.encodeWithSelector(IUniswapV2Pair.swap.selector, amount0Out, amount1Out, address(user), new bytes(0))
        );

        assert(!success);
    }

    event debugRoundTrip(uint256 amountIn, uint256 amountMid, uint256 amountBack);

    // function testSwapRoundTripPathIndependence(uint256 amountIn, uint256 liquidity0, uint256 liquidity1) public {
    //     (uint256 reserve0, uint256 reserve1) = _getReserves(address(token0), address(token1));

    //     // seed the pool on first call
    //     _seedPool(reserve0, reserve1, liquidity0, liquidity1);

    //     token0.mint(address(user), reserve0); // guarantee funds
    //     amountIn = _between(amountIn, 1, reserve0);

    //     address[] memory pathAB = new address[](2);
    //     pathAB[0] = address(token0);
    //     pathAB[1] = address(token1);

    //     address[] memory pathBA = new address[](2);
    //     pathBA[0] = address(token1);
    //     pathBA[1] = address(token0);

    //     // leg 1: A -> B
    //     (bool ok1, uint256[] memory amounts1) = swapExactTokensForTokens(amountIn, 0, pathAB);
    //     if (!ok1) return;
    //     uint256 spentA = amounts1[0]; // wrapper re-bounds amountIn, so use what was actually spent
    //     uint256 gotB = amounts1[1];
    //     if (gotB == 0) return;

    //     // marginal price after leg 1, used to size the rounding tolerance (in A units)
    //     (uint256 r0, uint256 r1) = _getReserves(address(token0), address(token1));
    //     uint256 tolerance = r0 / (r1 == 0 ? 1 : r1) + 2;

    //     // leg 2: B -> A, swap back exactly what we received
    //     (bool ok2, uint256[] memory amounts2) = swapExactTokensForTokens(gotB, 0, pathBA);
    //     if (!ok2) return;
    //     if (amounts2[0] != gotB) return; // wrapper changed the input, round trip isn't clean
    //     uint256 backA = amounts2[1];

    //     emit debugRoundTrip(spentA, gotB, backA);

    //     // 1. never profit: fees + rounding always favor the pool
    //     assert(backA <= spentA);

    //     // 2. loss bounded by two fees: back >= spent * (997/1000)^2, minus rounding dust
    //     uint256 minBack = (spentA * 994009) / 1000000;
    //     minBack = minBack > tolerance ? minBack - tolerance : 0;
    //     assert(backA >= minBack);
    // }

    function _seedPool(uint256 reserve0, uint256 reserve1, uint256 liquidity0, uint256 liquidity1) internal {
        if (reserve0 == 0 || reserve1 == 0) {
            (bool added,,,) = addLiquidity(liquidity0, liquidity1);
            if (!added) return;
            (reserve0, reserve1) = _getReserves(address(token0), address(token1));
        }
    }
    // function _addLiquidity(uint256 amount0, uint256 amount1)
    //     internal
    //     returns (bool success, uint256 amountA, uint256 amountB, uint256 liquidity)
    // {
    //     (success, amountA, amountB, liquidity) = addLiquidity(amount0, amount1);
    // }
}
