// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Uniswap V3 factory method used to authenticate a pool.
interface IUniswapV3Factory {
    /// @notice Returns the pool for a token pair and fee tier.
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/// @notice Uniswap V3 pool methods required by the executor.
interface IUniswapV3Pool {
    /// @notice First pool token.
    function token0() external view returns (address);

    /// @notice Second pool token.
    function token1() external view returns (address);

    /// @notice Executes a swap and calls the recipient's V3 callback for payment.
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

/// @notice Callback invoked by a Uniswap V3 pool to collect the input owed.
interface IUniswapV3SwapCallback {
    /// @notice Pays a verified pool its positive token deltas.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
