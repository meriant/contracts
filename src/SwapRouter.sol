// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { ReentrancyGuard } from "solady/src/utils/ReentrancyGuard.sol";

import { RouteExecution } from "./core/RouteExecution.sol";
import { RouteTypes } from "./core/RouteTypes.sol";
import { ISwapRouter } from "./interfaces/ISwapRouter.sol";

/// @title SwapRouter
/// @notice Chain-agnostic entry point for executing routes produced by the aggregator API.
/// @dev Protocol-specific executors are trusted stateless modules invoked with `delegatecall`. The router retains
/// token custody, verifies observed balance changes, and forwards callback selectors to the active executor.
contract SwapRouter is RouteExecution, ReentrancyGuard {
    /// @notice Configures immutable dependencies and authorizes the initial executor set.
    /// @param initialOwner Account allowed to change executor authorization.
    /// @param wrappedNative_ Chain's wrapped-native ERC-20 token.
    /// @param permit2_ Permit2 contract for signed or previously granted allowances.
    /// @param initialExecutors Reviewed executor addresses enabled at deployment.
    constructor(
        address initialOwner,
        address wrappedNative_,
        address permit2_,
        address[] memory initialExecutors
    )
        RouteExecution(initialOwner, wrappedNative_, permit2_, initialExecutors)
    { }

    /// @inheritdoc ISwapRouter
    function exactInput(RouteTypes.ExactInputParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut) = _validateExactInput(params);
        _takeAllowanceInput(params.tokenIn, tokenIn, params.amountIn);
        return _exactInput(params, tokenIn, tokenOut);
    }

    /// @inheritdoc ISwapRouter
    function exactInputWithPermit2(
        RouteTypes.ExactInputParams calldata params,
        Permit2Permit calldata permitData
    )
        external
        payable
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut) = _validateExactInput(params);
        _takePermit2Input(params.tokenIn, tokenIn, params.amountIn, params.deadline, permitData);
        return _exactInput(params, tokenIn, tokenOut);
    }

    /// @dev Executes and settles a funded exact-input route.
    /// @param params Caller-supplied route and minimum output.
    /// @param tokenIn Normalized input token.
    /// @param tokenOut Normalized output token.
    /// @return amountOut Actual output delivered to the recipient.
    function _exactInput(
        RouteTypes.ExactInputParams calldata params,
        address tokenIn,
        address tokenOut
    )
        private
        returns (uint256 amountOut)
    {
        uint256 allocatedInput;
        uint256 routerAmountOut;
        for (uint256 pathIndex; pathIndex < params.paths.length;) {
            RouteTypes.ExactInputPath calldata path = params.paths[pathIndex];
            allocatedInput += path.amountIn;
            routerAmountOut += _executeExactInputPath(path, tokenIn, tokenOut);
            unchecked {
                ++pathIndex;
            }
        }
        if (allocatedInput != params.amountIn) revert IncorrectInputAmount(params.amountIn, allocatedInput);

        amountOut = _sendOutput(params.tokenOut, tokenOut, params.recipient, routerAmountOut);
        if (amountOut < params.amountOutMinimum) revert SlippageExceeded(params.amountOutMinimum, amountOut);

        emit SwapExecuted(
            msg.sender,
            params.recipient,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            false
        );
    }

    /// @inheritdoc ISwapRouter
    function exactOutput(RouteTypes.ExactOutputParams calldata params)
        external
        payable
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        (address tokenIn, address tokenOut) = _validateExactOutput(params);
        _takeAllowanceInput(params.tokenIn, tokenIn, params.amountInMaximum);
        return _exactOutput(params, tokenIn, tokenOut);
    }

    /// @inheritdoc ISwapRouter
    function exactOutputWithPermit2(
        RouteTypes.ExactOutputParams calldata params,
        Permit2Permit calldata permitData
    )
        external
        payable
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        (address tokenIn, address tokenOut) = _validateExactOutput(params);
        _takePermit2Input(params.tokenIn, tokenIn, params.amountInMaximum, params.deadline, permitData);
        return _exactOutput(params, tokenIn, tokenOut);
    }

    /// @dev Executes and settles a funded exact-output route.
    /// @param params Caller-supplied route, target output, and maximum input.
    /// @param tokenIn Normalized input token.
    /// @param tokenOut Normalized output token.
    /// @return amountIn Original input spent before refunding the unused maximum.
    function _exactOutput(
        RouteTypes.ExactOutputParams calldata params,
        address tokenIn,
        address tokenOut
    )
        private
        returns (uint256 amountIn)
    {
        (uint256 allocatedOutput, uint256 spent, uint256 routerAmountOut) =
            _executeExactOutputPaths(params.paths, tokenIn, tokenOut, params.amountInMaximum);
        amountIn = spent;
        if (allocatedOutput != params.amountOut) revert InvalidRoute();
        if (amountIn > params.amountInMaximum) revert InputLimitExceeded(params.amountInMaximum, amountIn);

        uint256 amountOut = _sendOutput(params.tokenOut, tokenOut, params.recipient, routerAmountOut);
        if (amountOut < params.amountOut) revert SlippageExceeded(params.amountOut, amountOut);

        _refundInput(params.tokenIn, tokenIn, params.amountInMaximum - amountIn);

        emit SwapExecuted(msg.sender, params.recipient, params.tokenIn, params.tokenOut, amountIn, amountOut, true);
    }

    /// @dev Validates exact-input parameters before collecting the caller's funds.
    function _validateExactInput(RouteTypes.ExactInputParams calldata params)
        private
        view
        returns (address tokenIn, address tokenOut)
    {
        (tokenIn, tokenOut) = _routeTokens(params.tokenIn, params.tokenOut);
        _validateCommon(tokenIn, tokenOut, params.recipient, params.deadline);
        if (params.amountIn == 0 || params.amountOutMinimum == 0 || params.paths.length == 0) revert InvalidAmount();
    }

    /// @dev Validates exact-output parameters before collecting the caller's funds.
    function _validateExactOutput(RouteTypes.ExactOutputParams calldata params)
        private
        view
        returns (address tokenIn, address tokenOut)
    {
        (tokenIn, tokenOut) = _routeTokens(params.tokenIn, params.tokenOut);
        _validateCommon(tokenIn, tokenOut, params.recipient, params.deadline);
        if (params.amountOut == 0 || params.amountInMaximum == 0 || params.paths.length == 0) revert InvalidAmount();
    }

    /// @dev Rejects expired swaps, invalid recipients, and identical accounting tokens.
    /// @param tokenIn Normalized input token used for route accounting.
    /// @param tokenOut Normalized output token used for route accounting.
    /// @param recipient Account receiving the final output.
    /// @param deadline Last valid execution timestamp.
    function _validateCommon(address tokenIn, address tokenOut, address recipient, uint256 deadline) private view {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline);
        if (recipient == address(0) || recipient == address(this)) revert InvalidAddress();
        if (tokenIn == tokenOut) revert InvalidRoute();
    }

    /// @dev Only a direct native/wrapped-native conversion keeps the native address in route accounting.
    /// @param tokenIn Raw input token, with zero denoting native currency.
    /// @param tokenOut Raw output token, with zero denoting native currency.
    /// @return accountingIn Token used for the first route step.
    /// @return accountingOut Token required from the final route step.
    function _routeTokens(
        address tokenIn,
        address tokenOut
    )
        private
        view
        returns (address accountingIn, address accountingOut)
    {
        address wrapped = _normalizeToken(address(0));
        if ((tokenIn == address(0) && tokenOut == wrapped) || (tokenOut == address(0) && tokenIn == wrapped)) {
            return (tokenIn, tokenOut);
        }
        return (_normalizeToken(tokenIn), _normalizeToken(tokenOut));
    }
}
