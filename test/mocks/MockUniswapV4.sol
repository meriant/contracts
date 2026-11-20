// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {
    IUniswapV4PoolManager,
    IUniswapV4UnlockCallback,
    PoolKey,
    SwapParams
} from "../../src/interfaces/protocols/IUniswapV4.sol";

contract MockUniswapV4PoolManager is IUniswapV4PoolManager {
    using SafeERC20 for IERC20;

    error InvalidState();
    error NativeTransferFailed();

    address private locker;
    address private inputCurrency;
    address private outputCurrency;
    uint256 private expectedInput;
    uint256 private availableOutput;
    uint256 private syncedBalance;
    bool private settled;
    bool private taken;

    receive() external payable { }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        if (locker != address(0)) revert InvalidState();
        locker = msg.sender;
        result = IUniswapV4UnlockCallback(msg.sender).unlockCallback(data);
        if (!settled || !taken) revert InvalidState();
        locker = address(0);
        delete inputCurrency;
        delete outputCurrency;
        delete expectedInput;
        delete availableOutput;
        delete syncedBalance;
        delete settled;
        delete taken;
    }

    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        returns (int256 swapDelta)
    {
        if (msg.sender != locker) revert InvalidState();
        bool exactInput = params.amountSpecified < 0;
        uint256 specified = uint256(exactInput ? -params.amountSpecified : params.amountSpecified);
        expectedInput = exactInput ? specified : (specified + 1) / 2;
        availableOutput = exactInput ? specified * 2 : specified;
        inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;

        int128 inputDelta = -SafeCast.toInt128(SafeCast.toInt256(expectedInput));
        int128 outputDelta = SafeCast.toInt128(SafeCast.toInt256(availableOutput));
        (int128 amount0, int128 amount1) = params.zeroForOne ? (inputDelta, outputDelta) : (outputDelta, inputDelta);
        swapDelta = _pack(amount0, amount1);
    }

    function sync(address currency) external {
        if (msg.sender != locker || currency != inputCurrency) revert InvalidState();
        syncedBalance = IERC20(currency).balanceOf(address(this));
    }

    function take(address currency, address to, uint256 amount) external {
        if (msg.sender != locker || currency != outputCurrency || amount != availableOutput) revert InvalidState();
        taken = true;
        if (currency == address(0)) {
            (bool success,) = to.call{ value: amount }("");
            if (!success) revert NativeTransferFailed();
        } else {
            IERC20(currency).safeTransfer(to, amount);
        }
    }

    function settle() external payable returns (uint256 paid) {
        if (msg.sender != locker) revert InvalidState();
        if (inputCurrency == address(0)) {
            paid = msg.value;
        } else {
            paid = IERC20(inputCurrency).balanceOf(address(this)) - syncedBalance;
        }
        if (paid != expectedInput) revert InvalidState();
        settled = true;
    }

    function sendNative(address recipient, uint256 amount) external {
        (bool success, bytes memory result) = recipient.call{ value: amount }("");
        if (!success) {
            // solhint-disable-next-line no-inline-assembly
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    function _pack(int128 amount0, int128 amount1) private pure returns (int256 packed) {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            packed := or(shl(128, amount0), and(amount1, 0xffffffffffffffffffffffffffffffff))
        }
    }
}
