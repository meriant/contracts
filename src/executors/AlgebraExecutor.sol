// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IExecutor } from "../interfaces/IExecutor.sol";
import { IAlgebraFactory, IAlgebraPool, IAlgebraSwapCallback } from "../interfaces/protocols/IAlgebra.sol";

/// @notice Executes SparkDEX V4 swaps against its Algebra Integral factory.
contract AlgebraExecutor is IExecutor, IAlgebraSwapCallback {
    using SafeTransferLib for address;

    uint160 private constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 private constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    address public immutable FACTORY;

    struct SwapData {
        address pool;
        address deployer;
        uint160 sqrtPriceLimitX96;
    }

    struct CallbackData {
        address deployer;
        address tokenIn;
        address tokenOut;
    }

    error InvalidFactory(address factory);
    error InvalidPool(address pool);
    error InvalidSwapAmount(uint256 amount);
    error InvalidSwapCallback(address caller);
    error InvalidSwapDeltas(int256 amount0Delta, int256 amount1Delta);
    error InputLimitExceeded(uint256 maximum, uint256 actual);

    constructor(address factory_) {
        if (factory_ == address(0)) revert InvalidFactory(factory_);
        FACTORY = factory_;
    }

    /// @dev `data` is `abi.encode(pool, customPoolDeployer, sqrtPriceLimitX96)`. A zero deployer selects a regular
    /// pool.
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
        _checkAmount(amountIn);
        (, amountOut) = _swap(tokenIn, tokenOut, SafeCast.toInt256(amountIn), data);
    }

    /// @dev `data` has the same shape as `swapExactInput`.
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
        _checkAmount(amountOut);
        (amountIn,) = _swap(tokenIn, tokenOut, -SafeCast.toInt256(amountOut), data);
        if (amountIn > amountInMaximum) revert InputLimitExceeded(amountInMaximum, amountIn);
    }

    function _swap(
        address tokenIn,
        address tokenOut,
        int256 amountSpecified,
        bytes calldata data
    )
        private
        returns (uint256 amountIn, uint256 amountOut)
    {
        SwapData memory swapData = abi.decode(data, (SwapData));
        bool zeroForOne = _validatePool(swapData.pool, swapData.deployer, tokenIn, tokenOut);

        (int256 amount0, int256 amount1) = _callSwap(swapData, tokenIn, tokenOut, zeroForOne, amountSpecified);
        amountIn = _inputAmount(zeroForOne, amount0, amount1);
        amountOut = _outputAmount(zeroForOne, amount0, amount1);
    }

    function _callSwap(
        SwapData memory swapData,
        address tokenIn,
        address tokenOut,
        bool zeroForOne,
        int256 amountSpecified
    )
        private
        returns (int256 amount0, int256 amount1)
    {
        return IAlgebraPool(swapData.pool)
            .swap(
                address(this),
                zeroForOne,
                amountSpecified,
                _priceLimit(zeroForOne, swapData.sqrtPriceLimitX96),
                abi.encode(CallbackData({ deployer: swapData.deployer, tokenIn: tokenIn, tokenOut: tokenOut }))
            );
    }

    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        CallbackData memory callback = abi.decode(data, (CallbackData));
        address expected = callback.deployer == address(0)
            ? IAlgebraFactory(FACTORY).poolByPair(callback.tokenIn, callback.tokenOut)
            : IAlgebraFactory(FACTORY).customPoolByPair(callback.deployer, callback.tokenIn, callback.tokenOut);
        if (msg.sender != expected) revert InvalidSwapCallback(msg.sender);

        bool zeroForOne = callback.tokenIn == IAlgebraPool(msg.sender).token0();
        uint256 amount = _inputAmount(zeroForOne, amount0Delta, amount1Delta);
        callback.tokenIn.safeTransfer(msg.sender, amount);
    }

    function _validatePool(
        address pool,
        address deployer,
        address tokenIn,
        address tokenOut
    )
        private
        view
        returns (bool zeroForOne)
    {
        address expected = deployer == address(0)
            ? IAlgebraFactory(FACTORY).poolByPair(tokenIn, tokenOut)
            : IAlgebraFactory(FACTORY).customPoolByPair(deployer, tokenIn, tokenOut);
        if (pool == address(0) || expected != pool) revert InvalidPool(pool);

        address token0 = IAlgebraPool(pool).token0();
        address token1 = IAlgebraPool(pool).token1();
        if (tokenIn == token0 && tokenOut == token1) return true;
        if (tokenIn == token1 && tokenOut == token0) return false;
        revert InvalidPool(pool);
    }

    function _checkAmount(uint256 amount) private pure {
        if (amount == 0 || amount > uint256(type(int256).max)) revert InvalidSwapAmount(amount);
    }

    function _priceLimit(bool zeroForOne, uint160 limit) private pure returns (uint160) {
        return limit == 0 ? (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1) : limit;
    }

    function _inputAmount(bool zeroForOne, int256 amount0, int256 amount1) private pure returns (uint256 amount) {
        int256 delta = zeroForOne ? amount0 : amount1;
        if (delta <= 0) revert InvalidSwapDeltas(amount0, amount1);
        amount = SafeCast.toUint256(delta);
    }

    function _outputAmount(bool zeroForOne, int256 amount0, int256 amount1) private pure returns (uint256 amount) {
        int256 delta = zeroForOne ? amount1 : amount0;
        if (delta >= 0) revert InvalidSwapDeltas(amount0, amount1);
        amount = SafeCast.toUint256(-delta);
    }
}
