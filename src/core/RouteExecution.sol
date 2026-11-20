// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ExecutorDispatcher } from "./ExecutorDispatcher.sol";
import { RouteTypes } from "./RouteTypes.sol";
import { RouterPayments } from "./RouterPayments.sol";
import { IExecutor } from "../interfaces/IExecutor.sol";
import { INativeCurrencyExecutor } from "../interfaces/INativeCurrencyExecutor.sol";

/// @title RouteExecution
/// @notice Executes route steps and verifies observed token balance changes.
/// @dev The router holds custody. Executors run by delegatecall and may receive protocol callbacks only while active.
abstract contract RouteExecution is ExecutorDispatcher, RouterPayments {
    using SafeTransferLib for address;

    /// @notice Connects route execution to the executor registry and payment dependencies.
    /// @param initialOwner Account authorized to update the executor allowlist.
    /// @param wrappedNative_ Chain's wrapped-native ERC-20 token.
    /// @param permit2_ Permit2 allowance contract.
    /// @param initialExecutors Executor addresses enabled at deployment.
    constructor(
        address initialOwner,
        address wrappedNative_,
        address permit2_,
        address[] memory initialExecutors
    )
        ExecutorDispatcher(initialOwner, initialExecutors)
        RouterPayments(wrappedNative_, permit2_)
    { }

    /// @notice Accepts native currency from WETH withdrawals or the active executor's settlement contract.
    /// @dev The latter is needed by protocols that settle in native currency during a callback.
    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        if (msg.sender == wrappedNative) return;

        address executor = activeExecutor;
        if (executor == address(0)) revert UnexpectedCallback(msg.sig, msg.sender);

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) =
            executor.staticcall(abi.encodeCall(INativeCurrencyExecutor.nativeCurrencySender, ()));
        if (!success || result.length != 32 || abi.decode(result, (address)) != msg.sender) {
            revert UnexpectedCallback(msg.sig, msg.sender);
        }
    }

    /// @notice Executes exact-output paths against the shared input ceiling.
    /// @dev Each path's final step declares its output allocation. Unused original input is refunded by the router.
    /// @param paths Ordered paths in the route.
    /// @param tokenIn Accounting input token, or zero for a direct conversion.
    /// @param tokenOut Accounting output token, or zero for a direct conversion.
    /// @param amountInMaximum Global input ceiling shared by all paths.
    /// @return allocatedOutput Sum of the final output target of each path.
    /// @return amountIn Original input spent across all paths.
    /// @return amountOut Output actually produced across all paths.
    function _executeExactOutputPaths(
        RouteTypes.ExactOutputPath[] calldata paths,
        address tokenIn,
        address tokenOut,
        uint256 amountInMaximum
    )
        internal
        returns (uint256 allocatedOutput, uint256 amountIn, uint256 amountOut)
    {
        for (uint256 pathIndex; pathIndex < paths.length;) {
            RouteTypes.ExactOutputPath calldata path = paths[pathIndex];
            if (path.steps.length == 0) revert InvalidRoute();
            allocatedOutput += path.steps[path.steps.length - 1].amountOut;
            uint256 remainingInput = amountInMaximum - amountIn;
            (uint256 pathAmountIn, uint256 pathAmountOut) =
                _executeExactOutputPath(path, tokenIn, tokenOut, remainingInput);
            amountIn += pathAmountIn;
            amountOut += pathAmountOut;
            unchecked {
                ++pathIndex;
            }
        }
    }

    /// @notice Executes one exact-input path from its allocated input through ordered steps.
    /// @param path Path with an input allocation and ordered executor steps.
    /// @param routeTokenIn Accounting input token for the route.
    /// @param routeTokenOut Accounting output token for the route.
    /// @return amountOut Output actually produced by the path.
    function _executeExactInputPath(
        RouteTypes.ExactInputPath calldata path,
        address routeTokenIn,
        address routeTokenOut
    )
        internal
        returns (uint256 amountOut)
    {
        if (path.amountIn == 0 || path.steps.length == 0) revert InvalidRoute();
        _validateNativePath(path.steps.length, routeTokenIn, routeTokenOut);

        amountOut = path.amountIn;
        address expectedTokenIn = routeTokenIn;
        for (uint256 stepIndex; stepIndex < path.steps.length;) {
            RouteTypes.ExactInputStep calldata step = path.steps[stepIndex];
            if (step.tokenOut == address(0) && routeTokenOut != address(0)) revert InvalidRoute();
            _validateStep(step.executor, expectedTokenIn, step.tokenOut, step.data);

            amountOut = _executeExactInputStep(step, expectedTokenIn, amountOut);
            expectedTokenIn = step.tokenOut;
            unchecked {
                ++stepIndex;
            }
        }
        if (expectedTokenIn != routeTokenOut) revert InvalidRoute();
    }

    /// @notice Executes one exact-output path and returns observed original input and final output.
    /// @param path Path with ordered executor steps and output targets.
    /// @param routeTokenIn Accounting input token for the route.
    /// @param routeTokenOut Accounting output token for the route.
    /// @param amountInMaximum Input ceiling remaining for this path.
    /// @return amountIn Original input spent by the path.
    /// @return amountOut Output actually produced by the path.
    function _executeExactOutputPath(
        RouteTypes.ExactOutputPath calldata path,
        address routeTokenIn,
        address routeTokenOut,
        uint256 amountInMaximum
    )
        private
        returns (uint256 amountIn, uint256 amountOut)
    {
        if (path.steps.length == 0) revert InvalidRoute();
        _validateNativePath(path.steps.length, routeTokenIn, routeTokenOut);

        uint256 availableInput = amountInMaximum;
        address expectedTokenIn = routeTokenIn;
        for (uint256 stepIndex; stepIndex < path.steps.length;) {
            RouteTypes.ExactOutputStep calldata step = path.steps[stepIndex];
            if (step.amountOut == 0) revert InvalidRoute();
            if (step.tokenOut == address(0) && routeTokenOut != address(0)) revert InvalidRoute();
            _validateStep(step.executor, expectedTokenIn, step.tokenOut, step.data);

            (uint256 spent, uint256 received) = _executeExactOutputStep(step, expectedTokenIn, availableInput);

            if (stepIndex == 0) {
                amountIn = spent;
            } else if (spent < availableInput) {
                expectedTokenIn.safeTransfer(msg.sender, availableInput - spent);
            }

            availableInput = received;
            expectedTokenIn = step.tokenOut;
            unchecked {
                ++stepIndex;
            }
        }
        if (expectedTokenIn != routeTokenOut) revert InvalidRoute();
        amountOut = availableInput;
    }

    /// @notice Executes a hop and checks that observed balance changes match its exact input and reported output.
    /// @param step Executor, output token, and protocol data for this hop.
    /// @param tokenIn Input token for this hop.
    /// @param amountIn Exact input allocated to this hop.
    /// @return amountOut Output actually produced by this hop.
    function _executeExactInputStep(
        RouteTypes.ExactInputStep calldata step,
        address tokenIn,
        uint256 amountIn
    )
        private
        returns (uint256 amountOut)
    {
        uint256 inputBefore = _balanceOf(tokenIn);
        uint256 outputBefore = _balanceOf(step.tokenOut);

        bytes memory result;
        if (step.executor == address(0)) {
            _convertNative(tokenIn, step.tokenOut, amountIn);
        } else {
            result = _delegateToExecutor(
                step.executor, abi.encodeCall(IExecutor.swapExactInput, (tokenIn, step.tokenOut, amountIn, step.data))
            );
        }

        uint256 amountSpent = _decrease(tokenIn, inputBefore, _balanceOf(tokenIn));
        amountOut = _increase(step.tokenOut, outputBefore, _balanceOf(step.tokenOut));
        if (amountSpent != amountIn) revert IncorrectInputAmount(amountIn, amountSpent);
        if (amountOut == 0) revert SlippageExceeded(1, 0);

        if (step.executor != address(0)) _verifyExecutorResult(result, amountOut);
    }

    /// @notice Executes a hop and checks its input ceiling, output target, and reported input.
    /// @param step Executor, output token, target amount, and protocol data for this hop.
    /// @param tokenIn Input token for this hop.
    /// @param amountInMaximum Maximum input this hop may spend.
    /// @return amountIn Input actually spent by this hop.
    /// @return amountOut Output actually produced by this hop.
    function _executeExactOutputStep(
        RouteTypes.ExactOutputStep calldata step,
        address tokenIn,
        uint256 amountInMaximum
    )
        private
        returns (uint256 amountIn, uint256 amountOut)
    {
        uint256 inputBefore = _balanceOf(tokenIn);
        uint256 outputBefore = _balanceOf(step.tokenOut);

        bytes memory result;
        if (step.executor == address(0)) {
            if (step.amountOut > amountInMaximum) revert InputLimitExceeded(amountInMaximum, step.amountOut);
            _convertNative(tokenIn, step.tokenOut, step.amountOut);
        } else {
            result = _delegateToExecutor(
                step.executor,
                abi.encodeCall(
                    IExecutor.swapExactOutput, (tokenIn, step.tokenOut, step.amountOut, amountInMaximum, step.data)
                )
            );
        }

        amountIn = _decrease(tokenIn, inputBefore, _balanceOf(tokenIn));
        amountOut = _increase(step.tokenOut, outputBefore, _balanceOf(step.tokenOut));
        if (amountIn > amountInMaximum) revert InputLimitExceeded(amountInMaximum, amountIn);
        if (amountOut < step.amountOut) revert SlippageExceeded(step.amountOut, amountOut);

        if (step.executor != address(0)) _verifyExecutorResult(result, amountIn);
    }

    /// @notice Checks executor authorization and token continuity for one hop.
    /// @param executor Executor requested by the route step.
    /// @param tokenIn Token supplied to the step.
    /// @param tokenOut Token required from the step.
    function _validateStep(address executor, address tokenIn, address tokenOut, bytes calldata data) private view {
        if (tokenIn == tokenOut) revert InvalidRoute();
        if (tokenIn == address(0) || tokenOut == address(0)) {
            address wrapped = _normalizeToken(address(0));
            if ((tokenIn != wrapped && tokenOut != wrapped) || executor != address(0) || data.length != 0) {
                revert InvalidRoute();
            }
            return;
        }
        if (!isExecutor[executor]) revert InvalidExecutor(executor);
    }

    /// @notice Compares an executor's single-word return value with the observed balance delta.
    /// @param result Raw executor return data.
    /// @param observed Balance change measured by the router.
    function _verifyExecutorResult(bytes memory result, uint256 observed) private pure {
        if (result.length != 32) revert ExecutorResultMismatch(0, observed);
        uint256 reported = abi.decode(result, (uint256));
        if (reported != observed) revert ExecutorResultMismatch(reported, observed);
    }

    /// @notice Restricts raw native currency routes to the direct conversion step.
    /// @param stepCount Number of hops in the path.
    /// @param tokenIn Accounting input token for the route.
    /// @param tokenOut Accounting output token for the route.
    function _validateNativePath(uint256 stepCount, address tokenIn, address tokenOut) private pure {
        if ((tokenIn == address(0) || tokenOut == address(0)) && stepCount != 1) revert InvalidRoute();
    }
}
