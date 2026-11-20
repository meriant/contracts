// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @title IWrappedNative
/// @notice Minimal interface shared by WETH, WFLR, and equivalent wrapped native tokens.
interface IWrappedNative {
    /// @notice Mints wrapped tokens to the caller in exchange for `msg.value` native currency.
    function deposit() external payable;

    /// @notice Burns the caller's wrapped tokens and returns the same amount of native currency.
    /// @param amount Amount of wrapped tokens to redeem.
    function withdraw(uint256 amount) external;
}
