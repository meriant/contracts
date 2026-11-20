// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { V3ExecutorBase } from "./V3ExecutorBase.sol";
import { ISlipstreamFactory } from "../interfaces/protocols/ISlipstream.sol";
import { IUniswapV3SwapCallback } from "../interfaces/protocols/IUniswapV3.sol";

/// @notice Executes Velodrome/Aerodrome Slipstream swaps whose pools are keyed by tick spacing.
contract SlipstreamExecutor is V3ExecutorBase, IUniswapV3SwapCallback {
    constructor(address factory_) V3ExecutorBase(factory_) { }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    function _poolFor(address tokenIn, address tokenOut, uint24 poolParameter)
        internal
        view
        override
        returns (address)
    {
        // Slipstream factory tick spacings are positive and capped below the signed int24 maximum.
        // forge-lint: disable-next-line(unsafe-typecast)
        return ISlipstreamFactory(FACTORY).getPool(tokenIn, tokenOut, int24(poolParameter));
    }
}
