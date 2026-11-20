// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { IExecutor } from "../../src/interfaces/IExecutor.sol";
import { MockCallbackPool } from "./MockCallbackPool.sol";

contract MockCallbackExecutor is IExecutor {
    using SafeERC20 for IERC20;

    error InvalidCallback(address sender);

    address private immutable POOL;

    constructor(address pool) {
        POOL = pool;
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata data
    )
        external
        payable
        override
        returns (uint256 amountOut)
    {
        (uint256 numerator, uint256 denominator) = abi.decode(data, (uint256, uint256));
        amountOut = amountIn * numerator / denominator;
        MockCallbackPool(POOL).swap(tokenIn, tokenOut, amountIn, amountOut);
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes calldata data
    )
        external
        payable
        override
        returns (uint256 amountIn)
    {
        (uint256 numerator, uint256 denominator) = abi.decode(data, (uint256, uint256));
        amountIn = _ceilDiv(amountOut * denominator, numerator);
        if (amountIn > amountInMaximum) revert ISwapRouter.InputLimitExceeded(amountInMaximum, amountIn);

        MockCallbackPool(POOL).swap(tokenIn, tokenOut, amountIn, amountOut);
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata data) external {
        if (msg.sender != POOL) revert InvalidCallback(msg.sender);
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        IERC20(tokenIn).safeTransfer(msg.sender, amountIn);
    }

    function ping() external pure returns (bool) {
        return true;
    }

    function _ceilDiv(uint256 value, uint256 denominator) private pure returns (uint256) {
        return value == 0 ? 0 : (value - 1) / denominator + 1;
    }
}
