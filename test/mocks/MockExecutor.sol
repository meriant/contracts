// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { IExecutor } from "../../src/interfaces/IExecutor.sol";

interface IMintableToken {
    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

contract MockExecutor is IExecutor {
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

        IMintableToken(tokenIn).burn(address(this), amountIn);
        IMintableToken(tokenOut).mint(address(this), amountOut);
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

        IMintableToken(tokenIn).burn(address(this), amountIn);
        IMintableToken(tokenOut).mint(address(this), amountOut);
    }

    function _ceilDiv(uint256 value, uint256 denominator) private pure returns (uint256) {
        return value == 0 ? 0 : (value - 1) / denominator + 1;
    }
}
