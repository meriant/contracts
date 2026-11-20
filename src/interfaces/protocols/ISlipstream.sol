// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Slipstream factory method used to authenticate a pool by pair and tick spacing.
interface ISlipstreamFactory {
    /// @notice Returns the pool for a token pair and tick spacing.
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}
