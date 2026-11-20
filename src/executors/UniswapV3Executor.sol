// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { V3ExecutorBase } from "./V3ExecutorBase.sol";
import { IUniswapV3SwapCallback } from "../interfaces/protocols/IUniswapV3.sol";

/// @notice Executes Uniswap V3-compatible swaps and exposes only the protocol callback selector.
contract UniswapV3Executor is V3ExecutorBase, IUniswapV3SwapCallback {
    constructor(address factory_) V3ExecutorBase(factory_) { }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _swapCallback(amount0Delta, amount1Delta, data);
    }
}
