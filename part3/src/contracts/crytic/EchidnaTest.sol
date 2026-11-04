pragma solidity ^0.6.0;

import {Setup} from "./Setup.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {UniswapV2Library} from "../libraries/UniswapV2Library.sol";

contract EchidnaTest is Setup {
    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;
    // bootstrapping a pair needs sqrt(amount0 * amount1) > MINIMUM_LIQUIDITY, so
    // deposits are always at least 10**12; 10**24 keeps the reserves far away
    // from the pair's uint112 bound (2**112 - 1 ~ 5.2 * 10**33)
    uint256 internal constant MIN_DEPOSIT = 10 ** 12;
    uint256 internal constant MAX_DEPOSIT = 10 ** 24;

    function testProvideLiquidity(uint256 amount1, uint256 amount2) public {
        // preconditions
        amount1 = _between(amount1, 1000, uint256(-1));
        amount2 = _between(amount1, 1000, uint256(-1));

        if (!completed) {
            _mintTokens(amount1, amount2);
        }

        uint256 lpTokenBalanceBefore = pair.balanceOf(address(user));
        (uint256 reserve0Before, uint256 reserve1Before,) = pair.getReserves();
        uint256 kBefore = reserve0Before * reserve1Before;

        // @note we are transfering some amounts of token 1 and 2 to the pair contract
        (bool success1,) =
            user.proxy(address(token0), abi.encodeWithSelector(token0.transfer.selector, address(pair), amount1));
        (bool success2,) =
            user.proxy(address(token1), abi.encodeWithSelector(token1.transfer.selector, address(pair), amount2));
        require(success1 && success2);

        // action
        (bool success3,) =
            user.proxy(address(pair), abi.encodeWithSelector(bytes4(keccak256("mint(address)")), address(user)));

        // post conditions
        if (success3) {
            uint256 lpTokenBalanceAfter = pair.balanceOf(address(user));
            (uint256 reserve0After, uint256 reserve1After,) = pair.getReserves();
            uint256 kAfter = reserve0After * reserve1After;
            assert(lpTokenBalanceBefore < lpTokenBalanceAfter);
            assert(kBefore < kAfter);
        }
    }

    function testUserGetsCorrectAmountAfterSwap(uint256 amountInSeed) public {
        // pre conditions
        uint256 amountIn = _between(amountInSeed, MIN_DEPOSIT, MAX_DEPOSIT);
        require(_ensureLiquidity(amountIn, amountIn));

        // check the actual token ordering in the pair
        address inputToken;
        if (pair.token0() == address(token0)) {
            inputToken = address(token0);
            token0.mint(address(user), amountIn);
        } else {
            inputToken = address(token1);
            token1.mint(address(user), amountIn);
        }

        // transfer input tokens from user to the pair
        (bool transferSuccess,) = user.proxy(
            inputToken, abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(pair), amountIn)
        );
        require(transferSuccess, "Input transfer failed");

        // calculate expected output using the pair's actual reserves
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        uint256 amount1Out = UniswapV2Library.getAmountOut(amountIn, reserve0, reserve1);

        uint256 userBalanceBefore = _userBalance1();

        // action
        (bool success,) = user.proxy(
            address(pair),
            abi.encodeWithSelector(
                bytes4(keccak256("swap(uint256,uint256,address,bytes)")), 0, amount1Out, address(user), bytes("")
            )
        );

        // post conditions
        require(success, "Swap failed");

        uint256 userBalanceAfter = _userBalance1();
        assert(userBalanceAfter >= userBalanceBefore + amount1Out);
    }

    function testProvideLiquidityWhenTotalSupplyNonZero(uint256 seed1, uint256 seed2, uint256 amount1, uint256 amount2)
        public
    {
        // preconditions
        seed1 = _between(seed1, 1000, uint256(-1));
        seed2 = _between(seed2, 1000, uint256(-1));
        amount1 = _between(amount1, 1000, uint256(-1));
        amount2 = _between(amount2, 1000, uint256(-1));

        if (!completed) {
            _mintTokens(seed1 + amount1, seed2 + amount2);
        }

        // seed the pair with an initial liquidity position so that totalSupply != 0
        if (pair.totalSupply() == 0) {
            (bool seedSuccess1,) =
                user.proxy(address(token0), abi.encodeWithSelector(token0.transfer.selector, address(pair), seed1));
            (bool seedSuccess2,) =
                user.proxy(address(token1), abi.encodeWithSelector(token1.transfer.selector, address(pair), seed2));
            require(seedSuccess1 && seedSuccess2);

            (bool seedSuccess3,) =
                user.proxy(address(pair), abi.encodeWithSelector(bytes4(keccak256("mint(address)")), address(user)));
            require(seedSuccess3);
        }

        uint256 lpTokenBalanceBefore = pair.balanceOf(address(user));
        (uint256 reserve0Before, uint256 reserve1Before,) = pair.getReserves();
        uint256 kBefore = reserve0Before * reserve1Before;

        // @note we are transferring additional amounts of token 1 and 2 to the pair contract
        (bool success1,) =
            user.proxy(address(token0), abi.encodeWithSelector(token0.transfer.selector, address(pair), amount1));
        (bool success2,) =
            user.proxy(address(token1), abi.encodeWithSelector(token1.transfer.selector, address(pair), amount2));
        require(success1 && success2);

        // action
        (bool success3,) =
            user.proxy(address(pair), abi.encodeWithSelector(bytes4(keccak256("mint(address)")), address(user)));

        // post conditions
        if (success3) {
            uint256 lpTokenBalanceAfter = pair.balanceOf(address(user));
            (uint256 reserve0After, uint256 reserve1After,) = pair.getReserves();
            uint256 kAfter = reserve0After * reserve1After;
            // in the else block, liquidity = min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1)
            // so the user should still receive some LP tokens
            assert(lpTokenBalanceBefore < lpTokenBalanceAfter);
            // k should still grow when more liquidity is added (modulo the fee-on case)
            assert(kBefore < kAfter);
        }
    }

    // invariant 1: burn must always decrease the pool's LP token supply
    function testBurnDecreasesLpSupply(uint256 amount0, uint256 amount1, uint256 liquidity) public {
        // pre conditions
        amount0 = _between(amount0, MIN_DEPOSIT, MAX_DEPOSIT);
        amount1 = _between(amount1, MIN_DEPOSIT, MAX_DEPOSIT);

        _prepareBurn(amount0, amount1, liquidity);
        uint256 totalSupplyBefore = pair.totalSupply();
        require(totalSupplyBefore > 0);

        // actions
        (bool success,,) = _burnLiquidity(address(user));

        // post conditions
        if (success) {
            uint256 totalSupplyAfter = pair.totalSupply();
            assert(totalSupplyAfter < totalSupplyBefore);
        }
    }

    // invariant 2: burn must always decrease the pool's amount0 and amount1
    function testBurnDecreasesPoolBalances(uint256 amount0, uint256 amount1, uint256 liquidity) public {
        amount0 = _between(amount0, MIN_DEPOSIT, MAX_DEPOSIT);
        amount1 = _between(amount1, MIN_DEPOSIT, MAX_DEPOSIT);

        _prepareBurn(amount0, amount1, liquidity);

        // the reserves are only meaningful once they match the pair's real token
        // balances: earlier calls may have donated tokens to the pair without
        // minting them, and `burn` computes the paid amounts from the balances
        require(_sync());

        uint256 poolBalance0Before = _poolBalance0();
        uint256 poolBalance1Before = _poolBalance1();
        (uint256 reserve0Before, uint256 reserve1Before,) = pair.getReserves();

        // action
        (bool success, uint256 burned0, uint256 burned1) = _burnLiquidity(address(user));

        // post conditions
        if (success) {
            uint256 poolBalance0After = _poolBalance0();
            uint256 poolBalance1After = _poolBalance1();
            (uint256 reserve0After, uint256 reserve1After,) = pair.getReserves();

            // the burn paid out both tokens ...
            assert(burned0 > 0 && burned1 > 0);
            // ... and the pool gave away exactly those amounts ...
            assert(burned0 <= poolBalance0Before && burned1 <= poolBalance1Before);
            assert(poolBalance0After == poolBalance0Before - burned0);
            assert(poolBalance1After == poolBalance1Before - burned1);
            // ... so it holds strictly less of both tokens ...
            assert(poolBalance0After < poolBalance0Before);
            assert(poolBalance1After < poolBalance1Before);
            // ... and so are its reserves
            assert(reserve0After < reserve0Before);
            assert(reserve1After < reserve1Before);
        }
    }

    // invariant 3: the user's amount0 and amount1 must always increase after a burn
    function testBurnIncreasesUserBalances(uint256 amount0, uint256 amount1, uint256 liquidity) public {
        amount0 = _between(amount0, MIN_DEPOSIT, MAX_DEPOSIT);
        amount1 = _between(amount1, MIN_DEPOSIT, MAX_DEPOSIT);

        _prepareBurn(amount0, amount1, liquidity);

        // keep the pair's balances inside the uint112 reserves so that the burn
        // does not revert on the OVERFLOW check (the excess is skimmed away)
        require(_sync());

        uint256 userBalance0Before = _userBalance0();
        uint256 userBalance1Before = _userBalance1();

        // action
        (bool success, uint256 burned0, uint256 burned1) = _burnLiquidity(address(user));

        // post conditions
        if (success) {
            uint256 userBalance0After = _userBalance0();
            uint256 userBalance1After = _userBalance1();

            // the burn paid out both tokens ...
            assert(burned0 > 0 && burned1 > 0);
            // ... so the user's balances went up by exactly those amounts ...
            assert(userBalance0After == userBalance0Before + burned0);
            assert(userBalance1After == userBalance1Before + burned1);
            // ... and the user is strictly richer in both tokens
            assert(userBalance0After > userBalance0Before);
            assert(userBalance1After > userBalance1Before);
        }
    }

    // shared preconditions for the burn() tests: make sure the pair is initialized
    // and `user` owns some LP tokens, then send part of that position to the pair.
    // Returns `burned`, the LP balance the pair will actually destroy (a previous
    // call may have left LP tokens in the pair, and burn always uses balanceOf[pair])
    function _prepareBurn(uint256 amount0, uint256 amount1, uint256 liquidity) internal returns (uint256 burned) {
        require(_ensureLiquidity(amount0, amount1));
        uint256 userLiquidity = pair.balanceOf(address(user));
        require(userLiquidity > 0);
        liquidity = _between(liquidity, 1, userLiquidity);
        require(_sendLiquidityToPair(liquidity));
        burned = pair.balanceOf(address(pair));
        require(burned > 0);
    }

    function _prepareSwap() internal {
        // mint
        //
    }

    // --- helpers to read the tokens the pair actually holds ------------------------
    // the factory sorts the two tokens by address, so the pair's token0 is not
    // necessarily `token0`: always read the tokens back from the pair

    function _poolBalance0() internal view returns (uint256) {
        return IERC20(pair.token0()).balanceOf(address(pair));
    }

    function _poolBalance1() internal view returns (uint256) {
        return IERC20(pair.token1()).balanceOf(address(pair));
    }

    function _userBalance0() internal view returns (uint256) {
        return IERC20(pair.token0()).balanceOf(address(user));
    }

    function _userBalance1() internal view returns (uint256) {
        return IERC20(pair.token1()).balanceOf(address(user));
    }
}
