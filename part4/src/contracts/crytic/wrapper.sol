pragma solidity ^0.6.0;

import "./Setup.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../libraries/UniswapV2Library.sol";

abstract contract Wrapper is Setup {
    uint256 internal ghostDeposited0;
    uint256 internal ghostDeposited1;
    uint256 internal ghostWithdrawn0;
    uint256 internal ghostWithdrawn1;
    uint256 internal ghostDepositedETH;
    uint256 internal ghostWithdrawnETH;

    function addLiquidity(uint256 amount0, uint256 amount1)
        public
        returns (bool success, uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        amount0 = _between(amount0, 1001, uint112(-1));
        amount1 = _between(amount1, 1001, uint112(-1));

        _init(amount0, amount1);
        uint256 balance0 = token0.balanceOf(address(user));
        uint256 balance1 = token1.balanceOf(address(user));
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.addLiquidity.selector,
                address(token0),
                address(token1),
                amount0,
                amount1,
                0,
                0,
                address(user),
                uint256(-1)
            )
        );
        if (success) {
            (amountA, amountB, liquidity) = abi.decode(returnData, (uint256, uint256, uint256));
            ghostDeposited0 += balance0 - token0.balanceOf(address(user));
            ghostDeposited1 += balance1 - token1.balanceOf(address(user));
        }
    }

    function removeLiquidity(uint256 liquidity) public returns (bool success, uint256 amountA, uint256 amountB) {
        uint256 userLiquidity = testPair.balanceOf(address(user));
        if (userLiquidity == 0) {
            return (false, 0, 0);
        }
        liquidity = _between(liquidity, 1, userLiquidity);

        _doApprovals();
        uint256 balance0 = token0.balanceOf(address(user));
        uint256 balance1 = token1.balanceOf(address(user));

        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.removeLiquidity.selector,
                address(token0),
                address(token1),
                liquidity,
                0,
                0,
                address(user),
                uint256(-1)
            )
        );
        if (success) {
            (amountA, amountB) = abi.decode(returnData, (uint256, uint256));
            ghostWithdrawn0 += token0.balanceOf(address(user)) - balance0;
            ghostWithdrawn1 += token1.balanceOf(address(user)) - balance1;
        }
    }

    function addLiquidityETH(uint256 amountToken, uint256 amountETH)
        public
        payable
        returns (bool success, uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        amountToken = _between(amountToken, 1001, uint112(-1));
        if (address(this).balance < 1001) {
            return (false, 0, 0, 0);
        }
        amountETH = _between(amountETH, 1001, address(this).balance);

        _init(amountToken, 0);
        uint256 balance0 = token0.balanceOf(address(user));
        bytes memory returnData;
        (success, returnData) = user.proxy{value: amountETH}(
            address(router),
            abi.encodeWithSelector(
                router.addLiquidityETH.selector, address(token0), amountToken, 0, 0, address(user), uint256(-1)
            )
        );
        if (success) {
            (amountA, amountB, liquidity) = abi.decode(returnData, (uint256, uint256, uint256));
            ghostDeposited0 += balance0 - token0.balanceOf(address(user));
            ghostDepositedETH += amountB;
        }
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path)
        public
        returns (bool success, uint256[] memory amounts)
    {
        if (path.length < 2) {
            return (false, new uint256[](0));
        }
        uint256 userBalance = UniswapV2ERC20(path[0]).balanceOf(address(user));
        if (userBalance == 0) {
            return (false, new uint256[](0));
        }
        amountIn = _between(amountIn, 1, userBalance);

        _doApprovals();
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.swapExactTokensForTokens.selector, amountIn, amountOutMin, path, address(user), uint256(-1)
            )
        );
        if (success) {
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] memory path)
        public
        returns (bool success, uint256[] memory amounts)
    {
        if (path.length < 2) {
            return (false, new uint256[](0));
        }
        uint256 userBalance = UniswapV2ERC20(path[0]).balanceOf(address(user));
        if (userBalance == 0) {
            return (false, new uint256[](0));
        }
        amountOut = _between(amountOut, 1, uint112(-1));
        amountInMax = _between(amountInMax, 1, userBalance);

        _doApprovals();
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.swapTokensForExactTokens.selector, amountOut, amountInMax, path, address(user), uint256(-1)
            )
        );
        if (success) {
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    function removeLiquidityETH(uint256 liquidity) public returns (bool success, uint256 amountA, uint256 amountB) {
        address ethPair = UniswapV2Library.pairFor(address(factory), address(token0), address(weth));
        uint256 userLiquidity = IUniswapV2Pair(ethPair).balanceOf(address(user));
        if (userLiquidity == 0) {
            return (false, 0, 0);
        }
        liquidity = _between(liquidity, 1, userLiquidity);

        _doApprovals();
        uint256 balance0 = token0.balanceOf(address(user));
        uint256 balanceETH = address(user).balance;

        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.removeLiquidityETH.selector, address(token0), liquidity, 0, 0, address(user), uint256(-1)
            )
        );
        if (success) {
            (amountA, amountB) = abi.decode(returnData, (uint256, uint256));
            ghostWithdrawn0 += token0.balanceOf(address(user)) - balance0;
            ghostWithdrawnETH += address(user).balance - balanceETH;
        }
    }

    // @note for testing k decreases mutation
    function directSwapExactTokensForTokens(uint256 amountIn) public returns (bool success, uint256 amountOut) {
        address pairAddress = address(testPair);
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);

        uint256 userBalance = token0.balanceOf(address(user));

        if (userBalance == 0) {
            return (false, 0);
        }

        amountIn = _between(amountIn, 1, userBalance);

        // Get reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        if (reserve0 == 0 || reserve1 == 0) {
            return (false, 0);
        }

        // Calculate output WITHOUT the 0.3% fee
        amountOut = (amountIn * uint256(reserve1)) / uint256(reserve0);

        if (amountOut == 0) {
            return (false, 0);
        }

        // Transfer token0 directly from user to pair
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(token0),
            abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), pairAddress, amountIn)
        );

        if (!success || !abi.decode(returnData, (bool))) {
            return (false, 0);
        }

        // Direct pair interaction, bypassing router
        pair.swap(0, amountOut, address(user), new bytes(0));

        return (true, amountOut);
    }

    // ---------------------------------------------------------------
    // ETH swaps (path is built internally: WETH <-> token0, since the
    // router requires WETH at path[0] / path[last])
    // ---------------------------------------------------------------
    function swapExactETHForTokens(uint256 amountETH, uint256 amountOutMin)
        public
        payable
        returns (bool success, uint256[] memory amounts)
    {
        if (address(this).balance == 0) {
            return (false, new uint256[](0));
        }
        amountETH = _between(amountETH, 1, address(this).balance);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0);

        bytes memory returnData;
        (success, returnData) = user.proxy{value: amountETH}(
            address(router),
            abi.encodeWithSelector(
                router.swapExactETHForTokens.selector, amountOutMin, path, address(user), uint256(-1)
            )
        );
        if (success) {
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    function swapETHForExactTokens(uint256 amountOut, uint256 amountETHMax)
        public
        payable
        returns (bool success, uint256[] memory amounts)
    {
        if (address(this).balance == 0) {
            return (false, new uint256[](0));
        }
        amountOut = _between(amountOut, 1, uint112(-1));
        amountETHMax = _between(amountETHMax, 1, address(this).balance);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(token0);

        bytes memory returnData;
        (success, returnData) = user.proxy{value: amountETHMax}(
            address(router),
            abi.encodeWithSelector(router.swapETHForExactTokens.selector, amountOut, path, address(user), uint256(-1))
        );
        if (success) {
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin)
        public
        returns (bool success, uint256[] memory amounts)
    {
        uint256 userBalance = token0.balanceOf(address(user));
        if (userBalance == 0) {
            return (false, new uint256[](0));
        }
        amountIn = _between(amountIn, 1, userBalance);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        _doApprovals();
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.swapExactTokensForETH.selector, amountIn, amountOutMin, path, address(user), uint256(-1)
            )
        );
        if (success) {
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax)
        public
        returns (bool success, uint256[] memory amounts)
    {
        uint256 userBalance = token0.balanceOf(address(user));
        if (userBalance == 0) {
            return (false, new uint256[](0));
        }
        amountOut = _between(amountOut, 1, uint112(-1));
        amountInMax = _between(amountInMax, 1, userBalance);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        _doApprovals();
        bytes memory returnData;
        (success, returnData) = user.proxy(
            address(router),
            abi.encodeWithSelector(
                router.swapTokensForExactETH.selector, amountOut, amountInMax, path, address(user), uint256(-1)
            )
        );
        if (success) {
            amounts = abi.decode(returnData, (uint256[]));
        }
    }

    // ---------------------------------------------------------------
    // View / pure library passthroughs (try/catch so invalid inputs
    // return success=false instead of reverting the whole call)
    // ---------------------------------------------------------------
    // function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
    //     public
    //     view
    //     returns (bool success, uint256 amountB)
    // {
    //     amountA = _between(amountA, 1, uint112(-1));
    //     reserveA = _between(reserveA, 1, uint112(-1));
    //     reserveB = _between(reserveB, 1, uint112(-1));
    //     try router.quote(amountA, reserveA, reserveB) returns (uint256 result) {
    //         return (true, result);
    //     } catch {
    //         return (false, 0);
    //     }
    // }

    // function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
    //     public
    //     view
    //     returns (bool success, uint256 amountOut)
    // {
    //     amountIn = _between(amountIn, 1, uint112(-1));
    //     reserveIn = _between(reserveIn, 1, uint112(-1));
    //     reserveOut = _between(reserveOut, 1, uint112(-1));
    //     try router.getAmountOut(amountIn, reserveIn, reserveOut) returns (uint256 result) {
    //         return (true, result);
    //     } catch {
    //         return (false, 0);
    //     }
    // }

    // function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
    //     public
    //     view
    //     returns (bool success, uint256 amountIn)
    // {
    //     amountOut = _between(amountOut, 1, uint112(-1));
    //     reserveIn = _between(reserveIn, 1, uint112(-1));
    //     reserveOut = _between(reserveOut, 1, uint112(-1));
    //     try router.getAmountIn(amountOut, reserveIn, reserveOut) returns (uint256 result) {
    //         return (true, result);
    //     } catch {
    //         return (false, 0);
    //     }
    // }

    // function getAmountsOut(uint256 amountIn, address[] memory path)
    //     public
    //     view
    //     returns (bool success, uint256[] memory amounts)
    // {
    //     if (path.length < 2) {
    //         return (false, new uint256[](0));
    //     }
    //     amountIn = _between(amountIn, 1, uint112(-1));
    //     try router.getAmountsOut(amountIn, path) returns (uint256[] memory result) {
    //         return (true, result);
    //     } catch {
    //         return (false, new uint256[](0));
    //     }
    // }

    // function getAmountsIn(uint256 amountOut, address[] memory path)
    //     public
    //     view
    //     returns (bool success, uint256[] memory amounts)
    // {
    //     if (path.length < 2) {
    //         return (false, new uint256[](0));
    //     }
    //     amountOut = _between(amountOut, 1, uint112(-1));
    //     try router.getAmountsIn(amountOut, path) returns (uint256[] memory result) {
    //         return (true, result);
    //     } catch {
    //         return (false, new uint256[](0));
    //     }
    // }
}
