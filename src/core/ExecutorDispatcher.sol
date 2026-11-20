// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { ExecutorRegistry } from "./ExecutorRegistry.sol";
import { IAlgebraSwapCallback } from "../interfaces/protocols/IAlgebra.sol";
import { IEnosysV3SwapCallback } from "../interfaces/protocols/IEnosysV3.sol";
import { IUniswapV3SwapCallback } from "../interfaces/protocols/IUniswapV3.sol";
import { IUniswapV4UnlockCallback } from "../interfaces/protocols/IUniswapV4.sol";

/// @title ExecutorDispatcher
/// @notice Runs trusted executors in router storage and forwards pool callbacks to the active executor.
abstract contract ExecutorDispatcher is ExecutorRegistry {
    /// @dev Set only while an authorized executor runs; pool callbacks use this target.
    address internal activeExecutor;

    /// @notice Initializes executor ownership and the initial authorization set.
    /// @param initialOwner Account authorized to update the executor allowlist.
    /// @param initialExecutors Executor addresses enabled at deployment.
    constructor(
        address initialOwner,
        address[] memory initialExecutors
    )
        ExecutorRegistry(initialOwner, initialExecutors)
    { }

    /// @dev Only protocol callbacks may enter the active executor through the router. Adding a new callback protocol
    /// requires reviewing and adding its selector here; otherwise executor functions could be reentered via fallback.
    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        address executor = activeExecutor;
        bytes4 selector = msg.sig;
        if (executor == address(0) || !_isPoolCallback(selector)) revert UnexpectedCallback(selector, msg.sender);

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), executor, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch success
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Runs an authorized executor and restores the callback target after its call.
    /// @dev Bubbles executor revert data so callers see protocol-specific failures.
    /// @param executor Executor to run in router context.
    /// @param callData ABI-encoded executor method call.
    /// @return result Raw return data from the executor.
    function _delegateToExecutor(address executor, bytes memory callData) internal returns (bytes memory result) {
        activeExecutor = executor;
        bool success;
        // solhint-disable-next-line avoid-low-level-calls
        (success, result) = executor.delegatecall(callData);
        activeExecutor = address(0);

        if (!success) {
            if (result.length == 0) revert ExecutorCallFailed(executor);
            // solhint-disable-next-line no-inline-assembly
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /// @notice Enumerates the only callback selectors that fallback may forward.
    /// @param selector Callback selector supplied to the router fallback.
    /// @return allowed Whether the selector belongs to a supported pool callback.
    function _isPoolCallback(bytes4 selector) private pure returns (bool allowed) {
        return selector == IAlgebraSwapCallback.algebraSwapCallback.selector
            || selector == IEnosysV3SwapCallback.enosysdexV3SwapCallback.selector
            || selector == IUniswapV3SwapCallback.uniswapV3SwapCallback.selector
            || selector == IUniswapV4UnlockCallback.unlockCallback.selector;
    }
}
