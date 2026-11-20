// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @title IPermit2
/// @notice Minimal Permit2 AllowanceTransfer interface used by the swap router.
interface IPermit2 {
    /// @notice Token allowance details signed by the owner.
    /// @param token ERC-20 token authorized for spending.
    /// @param amount Maximum authorized amount.
    /// @param expiration Last timestamp when the allowance may be used.
    /// @param nonce Current allowance nonce.
    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    /// @notice Permit2 allowance authorization for a single token and spender.
    /// @param details Token-specific allowance terms.
    /// @param spender Address authorized to use the allowance.
    /// @param sigDeadline Last timestamp when the signature may be submitted.
    struct PermitSingle {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    /// @notice Reads the owner's current allowance for a token and spender.
    /// @param owner Token owner.
    /// @param token ERC-20 token.
    /// @param spender Authorized spender.
    /// @return amount Remaining allowance.
    /// @return expiration Allowance expiry timestamp.
    /// @return nonce Current allowance nonce.
    function allowance(
        address owner,
        address token,
        address spender
    )
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);

    /// @notice Sets an allowance through an on-chain Permit2 approval.
    /// @param token ERC-20 token.
    /// @param spender Authorized spender.
    /// @param amount Maximum allowance.
    /// @param expiration Allowance expiry timestamp.
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    /// @notice Installs a signed PermitSingle allowance.
    /// @param owner Token owner who signed the permit.
    /// @param permitSingle Signed allowance terms.
    /// @param signature Owner's Permit2 signature.
    function permit(address owner, PermitSingle memory permitSingle, bytes calldata signature) external;

    /// @notice Transfers tokens under an existing Permit2 allowance.
    /// @param from Token owner.
    /// @param to Recipient.
    /// @param amount Amount to transfer.
    /// @param token ERC-20 token.
    function transferFrom(address from, address to, uint160 amount, address token) external;
}
