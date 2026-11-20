// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { ISwapRouter } from "../interfaces/ISwapRouter.sol";

/// @title ExecutorRegistry
/// @notice Owner-managed allowlist of trusted protocol executors.
/// @dev Inheriting the registry adds no external call to the swap path. Executor bytecode runs with router storage
/// through `delegatecall`, so only reviewed, stateless executors should be registered.
abstract contract ExecutorRegistry is ISwapRouter, Ownable2Step {
    mapping(address executor => bool enabled) public override isExecutor;

    /// @notice Assigns the owner and enables the initial reviewed executors.
    /// @param initialOwner Account authorized to update the executor allowlist.
    /// @param initialExecutors Executor addresses enabled at deployment.
    constructor(address initialOwner, address[] memory initialExecutors) Ownable(initialOwner) {
        for (uint256 index; index < initialExecutors.length;) {
            _setExecutor(initialExecutors[index], true);
            unchecked {
                ++index;
            }
        }
    }

    /// @inheritdoc ISwapRouter
    function setExecutor(address executor, bool enabled) external override onlyOwner {
        _setExecutor(executor, enabled);
    }

    /// @inheritdoc ISwapRouter
    function setExecutors(address[] calldata executors, bool enabled) external override onlyOwner {
        for (uint256 index; index < executors.length;) {
            _setExecutor(executors[index], enabled);
            unchecked {
                ++index;
            }
        }
    }

    /// @notice Applies one executor authorization change and emits its event.
    /// @param executor Executor address to update.
    /// @param enabled Whether the executor may run in router context.
    function _setExecutor(address executor, bool enabled) private {
        if (executor == address(0) || executor == address(this)) {
            revert InvalidExecutor(executor);
        }
        if (isExecutor[executor] == enabled) return;

        isExecutor[executor] = enabled;
        emit ExecutorSet(executor, enabled);
    }
}
