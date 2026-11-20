// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Optional executor capability used to authorize native settlement callbacks while it is active.
interface INativeCurrencyExecutor {
    /// @notice Returns the protocol address permitted to send native currency during an active executor call.
    /// @return sender Authorized protocol settlement address.
    function nativeCurrencySender() external view returns (address);
}
