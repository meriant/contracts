// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { RouteTypes } from "../core/RouteTypes.sol";

/// @title ISwapRouter
/// @notice Executes direct, multihop, and split routes assembled by the aggregator API.
/// @dev `address(0)` represents native currency in top-level inputs and outputs. Ordinary DEX steps use the configured
/// wrapped-native token. A direct native/wrapped-native conversion has one step with a zero executor, empty data,
/// and `address(0)` on the native side.
interface ISwapRouter {
    /// @notice Optional Permit2 allowance authorization embedded in the swap transaction.
    /// @dev Leave `signature` empty when a sufficient unexpired Permit2 allowance already exists.
    /// @param nonce Permit2 allowance nonce when supplying a signature; ignored for an existing allowance.
    /// @param signature Permit2 PermitSingle signature, or empty bytes to use an existing allowance.
    struct Permit2Permit {
        uint48 nonce;
        bytes signature;
    }

    /// @notice The route expired before execution.
    error DeadlineExpired(uint256 deadline);
    /// @notice A delegatecall to an executor failed without revert data.
    error ExecutorCallFailed(address executor);
    /// @notice An executor's return value differs from the router-observed balance delta.
    error ExecutorResultMismatch(uint256 reported, uint256 observed);
    /// @notice The supplied or spent input differs from the required amount.
    error IncorrectInputAmount(uint256 expected, uint256 received);
    /// @notice `msg.value` differs from the native input expected by the route.
    error IncorrectNativeAmount(uint256 expected, uint256 received);
    /// @notice An exact-output route spent more than its input ceiling.
    error InputLimitExceeded(uint256 maximum, uint256 actual);
    /// @notice A required address is zero or otherwise invalid for its role.
    error InvalidAddress();
    /// @notice A top-level amount or limit is zero.
    error InvalidAmount();
    /// @notice The executor is not registered or cannot be registered.
    error InvalidExecutor(address executor);
    /// @notice Route paths or steps are empty, discontinuous, or inconsistent with top-level parameters.
    error InvalidRoute();
    /// @notice Native currency could not be delivered to its recipient.
    error NativeTransferFailed(address recipient, uint256 amount);
    /// @notice Permit2 cannot represent an input amount above `uint160`.
    error Permit2AmountOverflow(uint256 amount);
    /// @notice Permit2 allowance expiration cannot represent the supplied deadline.
    error Permit2DeadlineOverflow(uint256 deadline);
    /// @notice The observed output is below its required minimum.
    error SlippageExceeded(uint256 minimum, uint256 actual);
    /// @notice A token balance changed in the opposite direction from the expected swap flow.
    error TokenBalanceInvariant(address token);
    /// @notice The router received an unsupported native transfer or callback.
    error UnexpectedCallback(bytes4 selector, address sender);

    /// @notice Emitted when an executor's authorization changes.
    /// @param executor Executor whose authorization changed.
    /// @param enabled Whether the executor may run in router context.
    event ExecutorSet(address indexed executor, bool enabled);
    /// @notice Emitted after a successful route and any exact-output refund.
    /// @param sender Account that paid for the swap.
    /// @param recipient Account that received the final output.
    /// @param tokenIn Input token; zero denotes native currency.
    /// @param tokenOut Output token; zero denotes native currency.
    /// @param amountIn Original input actually spent.
    /// @param amountOut Final amount delivered to the recipient.
    /// @param exactOutput Whether the caller specified an output target.
    event SwapExecuted(
        address indexed sender,
        address indexed recipient,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bool exactOutput
    );

    /// @notice Returns the chain's wrapped-native token used for ordinary DEX routes and direct conversions.
    function wrappedNative() external view returns (address);

    /// @notice Returns the Permit2 contract used by the explicit Permit2 entrypoints.
    function permit2() external view returns (address);

    /// @notice Returns whether `executor` may run in the router's storage context.
    function isExecutor(address executor) external view returns (bool);

    /// @notice Registers or unregisters a trusted executor.
    /// @dev Only the owner may call this function. Registration is a trust decision: executor code runs by
    /// delegatecall.
    /// @param executor Address of the stateless executor.
    /// @param enabled Whether to authorize or revoke it.
    function setExecutor(address executor, bool enabled) external;

    /// @notice Registers or unregisters multiple trusted executors atomically.
    /// @param executors Executor addresses to update.
    /// @param enabled Whether to authorize or revoke them.
    function setExecutors(address[] calldata executors, bool enabled) external;

    /// @notice Executes routes that spend exactly `params.amountIn` and require a global minimum output.
    /// @dev Requires router ERC-20 allowance for token input, or `msg.value == amountIn` for native input.
    /// @param params Route, recipient, deadline, and slippage limit.
    /// @return amountOut Actual amount delivered to `params.recipient`.
    function exactInput(RouteTypes.ExactInputParams calldata params) external payable returns (uint256 amountOut);

    /// @notice Executes an exact-input route using Permit2 authorization.
    /// @dev Native input uses `msg.value`; ERC-20 input uses Permit2. An empty signature uses an existing allowance.
    /// @param params Route, recipient, deadline, and slippage limit.
    /// @param permitData Permit2 authorization for ERC-20 input.
    /// @return amountOut Actual amount delivered to `params.recipient`.
    function exactInputWithPermit2(
        RouteTypes.ExactInputParams calldata params,
        Permit2Permit calldata permitData
    )
        external
        payable
        returns (uint256 amountOut);

    /// @notice Executes routes that acquire at least `params.amountOut` within a global maximum input.
    /// @dev Requires router ERC-20 allowance for token input, or `msg.value == amountInMaximum` for native input.
    /// @param params Route, recipient, deadline, and input ceiling.
    /// @return amountIn Actual original input spent; the remainder is refunded to `msg.sender`.
    function exactOutput(RouteTypes.ExactOutputParams calldata params) external payable returns (uint256 amountIn);

    /// @notice Executes an exact-output route using Permit2 authorization.
    /// @dev Native input uses `msg.value`; ERC-20 input uses Permit2. An empty signature uses an existing allowance.
    /// @param params Route, recipient, deadline, and input ceiling.
    /// @param permitData Permit2 authorization for ERC-20 input.
    /// @return amountIn Original input actually spent; the remainder is refunded to `msg.sender`.
    function exactOutputWithPermit2(
        RouteTypes.ExactOutputParams calldata params,
        Permit2Permit calldata permitData
    )
        external
        payable
        returns (uint256 amountIn);
}
