// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @title RouteTypes
/// @notice Shared route data used by the swap router and its off-chain encoder.
library RouteTypes {
    /// @notice One protocol-specific hop in an exact-input path.
    /// @param executor Registered protocol module, or zero for a direct native/wrapped-native conversion.
    /// @param tokenOut Token produced by this hop; zero only for a direct wrapped-native unwrap.
    /// @param data Protocol-specific payload decoded by the executor; empty for wrapped-native conversion.
    struct ExactInputStep {
        address executor;
        address tokenOut;
        bytes data;
    }

    /// @notice One protocol-specific hop in an exact-output path.
    /// @dev `amountOut` is required for every hop so mixed-protocol paths can execute sequentially.
    /// @param executor Registered protocol module, or zero for a direct native/wrapped-native conversion.
    /// @param tokenOut Token produced by this hop; zero only for a direct wrapped-native unwrap.
    /// @param amountOut Minimum output that this hop must produce.
    /// @param data Protocol-specific payload decoded by the executor; empty for wrapped-native conversion.
    struct ExactOutputStep {
        address executor;
        address tokenOut;
        uint256 amountOut;
        bytes data;
    }

    /// @notice One direct or multihop exact-input path.
    /// @param amountIn Exact input allocated to this path.
    /// @param steps Ordered protocol hops from the route input to the route output. Native/wrapped conversion has one.
    struct ExactInputPath {
        uint256 amountIn;
        ExactInputStep[] steps;
    }

    /// @notice One direct or multihop exact-output path.
    /// @param steps Ordered protocol hops from the route input to the route output. The last step's target is the path
    /// allocation. Native/wrapped conversion has one step.
    struct ExactOutputPath {
        ExactOutputStep[] steps;
    }

    /// @notice Parameters shared by direct, multihop, and split exact-input swaps.
    /// @param tokenIn ERC-20 input, or `address(0)` for native currency.
    /// @param tokenOut ERC-20 output, or `address(0)` for native currency.
    /// @param amountIn Exact total input; path inputs must sum to this value.
    /// @param amountOutMinimum Minimum amount the recipient must actually receive.
    /// @param recipient Destination of the final output.
    /// @param deadline Last timestamp at which execution is allowed.
    /// @param paths One path for direct/multihop execution, or multiple paths for a split.
    struct ExactInputParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMinimum;
        address recipient;
        uint256 deadline;
        ExactInputPath[] paths;
    }

    /// @notice Parameters shared by direct, multihop, and split exact-output swaps.
    /// @param tokenIn ERC-20 input, or `address(0)` for native currency.
    /// @param tokenOut ERC-20 output, or `address(0)` for native currency.
    /// @param amountOut Required aggregate output; path outputs must sum to this value.
    /// @param amountInMaximum Maximum aggregate original input that may be spent.
    /// @param recipient Destination of the final output.
    /// @param deadline Last timestamp at which execution is allowed.
    /// @param paths One path for direct/multihop execution, or multiple paths for a split.
    struct ExactOutputParams {
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
        uint256 amountInMaximum;
        address recipient;
        uint256 deadline;
        ExactOutputPath[] paths;
    }
}
