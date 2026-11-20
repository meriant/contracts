// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Callback invoked by an Enosys V3 pool to collect the input owed.
interface IEnosysV3SwapCallback {
    /// @notice Pays a verified pool its positive token deltas.
    function enosysdexV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
