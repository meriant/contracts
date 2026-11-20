// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { V3ExecutorBase } from "./V3ExecutorBase.sol";
import { IEnosysV3SwapCallback } from "../interfaces/protocols/IEnosysV3.sol";

/// @notice Executes Enosys V3 swaps and exposes only the Enosys callback selector.
contract EnosysV3Executor is V3ExecutorBase, IEnosysV3SwapCallback {
    constructor(address factory_) V3ExecutorBase(factory_) { }

    function enosysdexV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _swapCallback(amount0Delta, amount1Delta, data);
    }
}
