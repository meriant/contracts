// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";

interface IMockSwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

interface IMockMintableToken {
    function mint(address account, uint256 amount) external;
}

contract MockCallbackPool {
    error UnexpectedExecutorFunctionForwarded();

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
        // A pool may try another executor selector while a callback is active. The router must reject it.
        // solhint-disable-next-line avoid-low-level-calls
        (bool forwarded, bytes memory result) = msg.sender.call(abi.encodeWithSignature("ping()"));
        bytes memory expected = abi.encodeWithSelector(
            ISwapRouter.UnexpectedCallback.selector, bytes4(keccak256("ping()")), address(this)
        );
        if (forwarded || keccak256(result) != keccak256(expected)) revert UnexpectedExecutorFunctionForwarded();
        IMockSwapCallback(msg.sender).uniswapV3SwapCallback(0, 0, abi.encode(tokenIn, amountIn));
        IMockMintableToken(tokenOut).mint(msg.sender, amountOut);
    }
}
