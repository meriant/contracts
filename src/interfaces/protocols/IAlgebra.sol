// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Algebra factory methods used to authenticate a pool by its token pair.
interface IAlgebraFactory {
    /// @notice Returns the canonical pool for a token pair.
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

    /// @notice Returns a custom-deployer pool for a token pair.
    function customPoolByPair(address deployer, address tokenA, address tokenB) external view returns (address pool);
}

/// @notice Algebra pool methods required by the executor.
interface IAlgebraPool {
    /// @notice First pool token.
    function token0() external view returns (address);

    /// @notice Second pool token.
    function token1() external view returns (address);

    /// @notice Executes a swap and calls the recipient's Algebra callback for payment.
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1);
}

/// @notice Callback invoked by an Algebra pool to collect the input owed.
interface IAlgebraSwapCallback {
    /// @notice Pays a verified pool its positive token deltas.
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
