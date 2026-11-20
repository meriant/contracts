// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @title IExecutor
/// @notice Boundary between the swap router and a protocol-specific executor.
/// @dev Executors are trusted stateless modules invoked with `delegatecall`. Assets remain in the router, and an
/// executor must send output back to `address(this)`. The router independently verifies balance changes. Direct native
/// conversions are handled by the router, outside this interface.
interface IExecutor {
    /// @notice Swaps an exact amount of `tokenIn` for `tokenOut`.
    /// @param tokenIn Input token held by the router.
    /// @param tokenOut Output token returned to the router.
    /// @param amountIn Exact amount to spend.
    /// @param data Protocol-specific encoded pool and swap parameters.
    /// @return amountOut Amount of `tokenOut` produced, independently checked by the router.
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata data
    )
        external
        payable
        returns (uint256 amountOut);

    /// @notice Acquires at least `amountOut` while spending no more than `amountInMaximum`.
    /// @param tokenIn Input token held by the router.
    /// @param tokenOut Output token returned to the router.
    /// @param amountOut Output target for this hop.
    /// @param amountInMaximum Maximum input made available to this hop.
    /// @param data Protocol-specific encoded pool and swap parameters.
    /// @return amountIn Amount of `tokenIn` spent, independently checked by the router.
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata data
    )
        external
        payable
        returns (uint256 amountIn);
}
