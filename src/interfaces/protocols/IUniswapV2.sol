// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Uniswap V2 factory method used to authenticate a pair.
interface IUniswapV2Factory {
    /// @notice Returns the pair contract for two tokens, or zero when absent.
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @notice Uniswap V2 pair methods required by the executor.
interface IUniswapV2Pair {
    /// @notice First pair token.
    function token0() external view returns (address);

    /// @notice Second pair token.
    function token1() external view returns (address);

    /// @notice Current reserves and last reserve update timestamp.
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /// @notice Sends the requested output to `to` and checks the pair invariant.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
