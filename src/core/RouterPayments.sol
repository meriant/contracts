// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import { IPermit2 } from "../interfaces/IPermit2.sol";
import { IWrappedNative } from "../interfaces/IWrappedNative.sol";

/// @title RouterPayments
/// @notice Handles input custody, Permit2 transfers, native wrapping, outputs, and refunds for the router.
/// @dev A zero accounting token leaves native currency unwrapped for a direct conversion step.
abstract contract RouterPayments is ISwapRouter {
    using SafeTransferLib for address;

    /// @inheritdoc ISwapRouter
    // solhint-disable-next-line immutable-vars-naming
    address public immutable override wrappedNative;

    /// @inheritdoc ISwapRouter
    // solhint-disable-next-line immutable-vars-naming
    address public immutable override permit2;

    /// @notice Stores the chain's wrapped-native and Permit2 dependencies immutably.
    /// @param wrappedNative_ Chain's wrapped-native ERC-20 token.
    /// @param permit2_ Permit2 allowance contract.
    constructor(address wrappedNative_, address permit2_) {
        if (wrappedNative_ == address(0) || permit2_ == address(0)) revert InvalidAddress();

        wrappedNative = wrappedNative_;
        permit2 = permit2_;
    }

    /// @notice Collects input through an ERC-20 allowance granted directly to the router.
    /// @param rawToken Caller-facing token; zero denotes native currency.
    /// @param token Accounting token used by the route.
    /// @param amount Input amount to collect.
    function _takeAllowanceInput(address rawToken, address token, uint256 amount) internal {
        if (rawToken == address(0)) {
            _takeNativeInput(token, amount);
            return;
        }

        if (msg.value != 0) revert IncorrectNativeAmount(0, msg.value);
        uint256 balanceBefore = _balanceOf(token);
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = _increase(token, balanceBefore, _balanceOf(token));
        if (received != amount) revert IncorrectInputAmount(amount, received);
    }

    /// @notice Collects input through Permit2 using a new signature or an existing allowance.
    /// @param rawToken Caller-facing token; zero denotes native currency.
    /// @param token Accounting token used by the route.
    /// @param amount Exact amount to transfer.
    /// @param deadline Last timestamp for the signed Permit2 allowance.
    /// @param permitData Optional signature and nonce.
    function _takePermit2Input(
        address rawToken,
        address token,
        uint256 amount,
        uint256 deadline,
        Permit2Permit calldata permitData
    )
        internal
    {
        if (rawToken == address(0)) {
            _takeNativeInput(token, amount);
            return;
        }

        if (msg.value != 0) revert IncorrectNativeAmount(0, msg.value);
        uint256 balanceBefore = _balanceOf(token);
        if (amount > type(uint160).max) revert Permit2AmountOverflow(amount);
        if (deadline > type(uint48).max) revert Permit2DeadlineOverflow(deadline);

        // Safe after the explicit Permit2 width checks above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint160 permitAmount = uint160(amount);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint48 permitExpiration = uint48(deadline);
        IPermit2 permitContract = IPermit2(permit2);
        if (permitData.signature.length != 0) {
            permitContract.permit(
                msg.sender,
                IPermit2.PermitSingle({
                    details: IPermit2.PermitDetails({
                        token: token,
                        amount: permitAmount,
                        expiration: permitExpiration,
                        nonce: permitData.nonce
                    }),
                    spender: address(this),
                    sigDeadline: deadline
                }),
                permitData.signature
            );
        }

        permitContract.transferFrom(msg.sender, address(this), permitAmount, token);
        uint256 received = _increase(token, balanceBefore, _balanceOf(token));
        if (received != amount) revert IncorrectInputAmount(amount, received);
    }

    /// @dev Keeps direct conversion input native and wraps input for ordinary DEX routes.
    function _takeNativeInput(address token, uint256 amount) private {
        if (msg.value != amount) revert IncorrectNativeAmount(amount, msg.value);
        if (token != address(0)) IWrappedNative(wrappedNative).deposit{ value: amount }();
    }

    /// @notice Converts between native currency and its wrapped token in router custody.
    /// @param tokenIn Input token; zero denotes native currency.
    /// @param tokenOut Output token; zero denotes native currency.
    /// @param amount Amount to wrap or unwrap.
    function _convertNative(address tokenIn, address tokenOut, uint256 amount) internal {
        if (tokenIn == address(0) && tokenOut == wrappedNative) {
            IWrappedNative(wrappedNative).deposit{ value: amount }();
        } else if (tokenIn == wrappedNative && tokenOut == address(0)) {
            IWrappedNative(wrappedNative).withdraw(amount);
        } else {
            revert InvalidRoute();
        }
    }

    /// @notice Delivers final output and returns the amount actually received by the recipient.
    /// @param rawToken Caller-facing output token; zero denotes native currency.
    /// @param token Accounting token produced by the route.
    /// @param recipient Account receiving the output.
    /// @param amount Amount produced by the route.
    /// @return received Actual token amount received after any token transfer fee.
    function _sendOutput(
        address rawToken,
        address token,
        address recipient,
        uint256 amount
    )
        internal
        returns (uint256 received)
    {
        if (rawToken == address(0)) {
            if (token != address(0)) IWrappedNative(wrappedNative).withdraw(amount);
            _sendNative(recipient, amount);
            return amount;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        received = _increase(token, balanceBefore, IERC20(token).balanceOf(recipient));
    }

    /// @notice Returns unspent original input to the caller after an exact-output swap.
    /// @param rawToken Caller-facing input token; zero denotes native currency.
    /// @param token Accounting token held for the route.
    /// @param amount Unused original input to refund.
    function _refundInput(address rawToken, address token, uint256 amount) internal {
        if (amount == 0) return;

        if (rawToken == address(0)) {
            if (token != address(0)) IWrappedNative(wrappedNative).withdraw(amount);
            _sendNative(msg.sender, amount);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    /// @notice Uses wrapped-native ERC-20 accounting for ordinary native DEX routes.
    /// @param token Caller-facing token; zero denotes native currency.
    /// @return accountingToken ERC-20 address used in route accounting.
    function _normalizeToken(address token) internal view returns (address) {
        return token == address(0) ? wrappedNative : token;
    }

    /// @notice Reads the router's native balance for zero, or its ERC-20 balance for a token.
    /// @param token Token to measure; zero denotes native currency.
    /// @return balance Router balance of the token.
    function _balanceOf(address token) internal view returns (uint256 balance) {
        if (token == address(0)) return address(this).balance;
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Returns an observed increase, reverting if the balance decreased.
    /// @param token Token whose balance was measured.
    /// @param beforeBalance Balance before the external call.
    /// @param afterBalance Balance after the external call.
    /// @return increase Observed balance increase.
    function _increase(
        address token,
        uint256 beforeBalance,
        uint256 afterBalance
    )
        internal
        pure
        returns (uint256 increase)
    {
        if (afterBalance < beforeBalance) revert TokenBalanceInvariant(token);
        return afterBalance - beforeBalance;
    }

    /// @notice Returns an observed decrease, reverting if the balance increased.
    /// @param token Token whose balance was measured.
    /// @param beforeBalance Balance before the external call.
    /// @param afterBalance Balance after the external call.
    /// @return decrease Observed balance decrease.
    function _decrease(
        address token,
        uint256 beforeBalance,
        uint256 afterBalance
    )
        internal
        pure
        returns (uint256 decrease)
    {
        if (afterBalance > beforeBalance) revert TokenBalanceInvariant(token);
        return beforeBalance - afterBalance;
    }

    /// @notice Forwards native currency and reverts if the recipient rejects it.
    /// @param recipient Account receiving native currency.
    /// @param amount Native currency to send.
    function _sendNative(address recipient, uint256 amount) private {
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert NativeTransferFailed(recipient, amount);
    }
}
