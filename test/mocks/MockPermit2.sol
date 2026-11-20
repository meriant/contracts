// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPermit2 } from "../../src/interfaces/IPermit2.sol";

contract MockPermit2 is IPermit2 {
    using SafeERC20 for IERC20;

    error InvalidNonce();
    error InvalidSignature();
    error SignatureExpired();
    error AllowanceExpired();
    error InsufficientAllowance();

    struct Allowance {
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    mapping(address owner => mapping(address token => mapping(address spender => Allowance value)))
        public
        override allowance;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external override {
        Allowance storage current = allowance[msg.sender][token][spender];
        current.amount = amount;
        current.expiration = expiration;
    }

    function permit(address owner, PermitSingle memory permitSingle, bytes calldata signature) external override {
        if (signature.length == 0) revert InvalidSignature();
        if (block.timestamp > permitSingle.sigDeadline) revert SignatureExpired();

        PermitDetails memory details = permitSingle.details;
        Allowance storage current = allowance[owner][details.token][permitSingle.spender];
        if (current.nonce != details.nonce) revert InvalidNonce();

        current.amount = details.amount;
        current.expiration = details.expiration;
        current.nonce = details.nonce + 1;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external override {
        Allowance storage current = allowance[from][token][msg.sender];
        if (block.timestamp > current.expiration) revert AllowanceExpired();
        if (amount > current.amount) revert InsufficientAllowance();

        current.amount -= amount;
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
