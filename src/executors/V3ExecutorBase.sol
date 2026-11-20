// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IExecutor } from "../interfaces/IExecutor.sol";
import { IUniswapV3Factory, IUniswapV3Pool } from "../interfaces/protocols/IUniswapV3.sol";

/// @notice Shared swap logic for Uniswap V3-compatible protocols.
/// @dev Concrete executors expose only the callback selector used by their protocol.
abstract contract V3ExecutorBase is IExecutor {
    using SafeTransferLib for address;

    uint160 private constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 private constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    address public immutable FACTORY;

    struct SwapData {
        address pool;
        uint24 poolParameter;
        uint160 sqrtPriceLimitX96;
    }

    struct CallbackData {
        address tokenIn;
        address tokenOut;
        uint24 poolParameter;
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

    /// @dev `data` is `abi.encode(pool, poolParameter, sqrtPriceLimitX96)`. For Uniswap V3 the pool parameter is the
    /// fee; compatible executors may interpret the same word differently. A zero limit selects the full price range.
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

    function _swapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) internal {
        CallbackData memory callback = abi.decode(data, (CallbackData));
        if (_poolFor(callback.tokenIn, callback.tokenOut, callback.poolParameter) != msg.sender) {
            revert InvalidSwapCallback(msg.sender);
        }

        bool zeroForOne = callback.tokenIn == IUniswapV3Pool(msg.sender).token0();
        uint256 amount = _inputAmount(zeroForOne, amount0Delta, amount1Delta);
        callback.tokenIn.safeTransfer(msg.sender, amount);
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
        bool zeroForOne = _validatePool(swapData.pool, tokenIn, tokenOut, swapData.poolParameter);

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
        return IUniswapV3Pool(swapData.pool)
            .swap(
                address(this),
                zeroForOne,
                amountSpecified,
                _priceLimit(zeroForOne, swapData.sqrtPriceLimitX96),
                abi.encode(
                    CallbackData({ tokenIn: tokenIn, tokenOut: tokenOut, poolParameter: swapData.poolParameter })
                )
            );
    }

    function _validatePool(
        address pool,
        address tokenIn,
        address tokenOut,
        uint24 poolParameter
    )
        private
        view
        returns (bool zeroForOne)
    {
        if (pool == address(0) || _poolFor(tokenIn, tokenOut, poolParameter) != pool) {
            revert InvalidPool(pool);
        }

        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        if (tokenIn == token0 && tokenOut == token1) return true;
        if (tokenIn == token1 && tokenOut == token0) return false;
        revert InvalidPool(pool);
    }

    /// @dev Resolves the canonical pool for the encoded parameter. Slipstream overrides this to use tick spacing.
    function _poolFor(address tokenIn, address tokenOut, uint24 poolParameter) internal view virtual returns (address) {
        return IUniswapV3Factory(FACTORY).getPool(tokenIn, tokenOut, poolParameter);
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
