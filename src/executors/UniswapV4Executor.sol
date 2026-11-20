// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IExecutor } from "../interfaces/IExecutor.sol";
import { INativeCurrencyExecutor } from "../interfaces/INativeCurrencyExecutor.sol";
import { IWrappedNative } from "../interfaces/IWrappedNative.sol";
import {
    IUniswapV4PoolManager,
    IUniswapV4UnlockCallback,
    PoolKey,
    SwapParams
} from "../interfaces/protocols/IUniswapV4.sol";

/// @notice Executes hookless Uniswap V4 swaps through a PoolManager.
contract UniswapV4Executor is IExecutor, INativeCurrencyExecutor, IUniswapV4UnlockCallback {
    using SafeTransferLib for address;

    uint160 private constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 private constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;
    uint256 private constant MAX_SWAP_AMOUNT = (1 << 127) - 1;

    address public immutable POOL_MANAGER;
    address public immutable WRAPPED_NATIVE;

    struct CallbackData {
        address tokenIn;
        address tokenOut;
        int256 amountSpecified;
        PoolKey key;
    }

    error InvalidHooks(address hooks);
    error InvalidPoolKey();
    error InvalidPoolManager(address poolManager);
    error InvalidSettlement(uint256 expected, uint256 paid);
    error InvalidSwapAmount(uint256 amount);
    error InvalidSwapCallback(address caller);
    error InvalidSwapDeltas(int128 amount0Delta, int128 amount1Delta);
    error InvalidWrappedNative(address wrappedNative);
    error InputLimitExceeded(uint256 maximum, uint256 actual);

    constructor(address poolManager_, address wrappedNative_) {
        if (poolManager_ == address(0)) {
            revert InvalidPoolManager(poolManager_);
        }
        if (wrappedNative_ == address(0)) {
            revert InvalidWrappedNative(wrappedNative_);
        }
        POOL_MANAGER = poolManager_;
        WRAPPED_NATIVE = wrappedNative_;
    }

    /// @dev `data` is `abi.encode(currency0, currency1, fee, tickSpacing, hooks)`. Only hookless pools are supported.
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
        (, amountOut) = _swap(tokenIn, tokenOut, -SafeCast.toInt256(amountIn), data);
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
        (amountIn,) = _swap(tokenIn, tokenOut, SafeCast.toInt256(amountOut), data);
        if (amountIn > amountInMaximum) revert InputLimitExceeded(amountInMaximum, amountIn);
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory result) {
        if (msg.sender != POOL_MANAGER) revert InvalidSwapCallback(msg.sender);

        CallbackData memory callback = abi.decode(data, (CallbackData));
        bool zeroForOne = _validatePoolKey(callback.key, callback.tokenIn, callback.tokenOut);
        int256 packedDelta = IUniswapV4PoolManager(POOL_MANAGER)
            .swap(
                callback.key,
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: callback.amountSpecified,
                    sqrtPriceLimitX96: _priceLimit(zeroForOne)
                }),
                bytes("")
            );

        (int128 amount0Delta, int128 amount1Delta) = _unpack(packedDelta);
        (uint256 amountIn, uint256 amountOut) = _amounts(zeroForOne, amount0Delta, amount1Delta);
        _settle(callback.key, zeroForOne, amountIn);
        _take(callback.key, zeroForOne, amountOut);
        result = abi.encode(amountIn, amountOut);
    }

    function nativeCurrencySender() external view override returns (address) {
        return POOL_MANAGER;
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
        PoolKey memory key = abi.decode(data, (PoolKey));
        _validatePoolKey(key, tokenIn, tokenOut);
        bytes memory result = IUniswapV4PoolManager(POOL_MANAGER)
            .unlock(
                abi.encode(
                    CallbackData({ tokenIn: tokenIn, tokenOut: tokenOut, amountSpecified: amountSpecified, key: key })
                )
            );
        (amountIn, amountOut) = abi.decode(result, (uint256, uint256));
    }

    function _settle(PoolKey memory key, bool zeroForOne, uint256 amount) private {
        address currency = zeroForOne ? key.currency0 : key.currency1;
        uint256 paid;
        if (currency == address(0)) {
            IWrappedNative(WRAPPED_NATIVE).withdraw(amount);
            paid = IUniswapV4PoolManager(POOL_MANAGER).settle{ value: amount }();
        } else {
            IUniswapV4PoolManager(POOL_MANAGER).sync(currency);
            currency.safeTransfer(POOL_MANAGER, amount);
            paid = IUniswapV4PoolManager(POOL_MANAGER).settle();
        }
        if (paid != amount) revert InvalidSettlement(amount, paid);
    }

    function _take(PoolKey memory key, bool zeroForOne, uint256 amount) private {
        address currency = zeroForOne ? key.currency1 : key.currency0;
        IUniswapV4PoolManager(POOL_MANAGER).take(currency, address(this), amount);
        if (currency == address(0)) IWrappedNative(WRAPPED_NATIVE).deposit{ value: amount }();
    }

    function _validatePoolKey(
        PoolKey memory key,
        address tokenIn,
        address tokenOut
    )
        private
        view
        returns (bool zeroForOne)
    {
        if (key.hooks != address(0)) revert InvalidHooks(key.hooks);
        if (key.currency0 >= key.currency1) revert InvalidPoolKey();

        address token0 = key.currency0 == address(0) ? WRAPPED_NATIVE : key.currency0;
        address token1 = key.currency1 == address(0) ? WRAPPED_NATIVE : key.currency1;
        if (tokenIn == token0 && tokenOut == token1) return true;
        if (tokenIn == token1 && tokenOut == token0) return false;
        revert InvalidPoolKey();
    }

    function _checkAmount(uint256 amount) private pure {
        if (amount == 0 || amount > MAX_SWAP_AMOUNT) revert InvalidSwapAmount(amount);
    }

    function _priceLimit(bool zeroForOne) private pure returns (uint160) {
        return zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;
    }

    function _unpack(int256 packedDelta) private pure returns (int128 amount0, int128 amount1) {
        // forge-lint: disable-next-line(unsafe-typecast)
        amount0 = int128(packedDelta >> 128);
        // forge-lint: disable-next-line(unsafe-typecast)
        amount1 = int128(packedDelta);
    }

    function _amounts(
        bool zeroForOne,
        int128 amount0Delta,
        int128 amount1Delta
    )
        private
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        int128 inputDelta = zeroForOne ? amount0Delta : amount1Delta;
        int128 outputDelta = zeroForOne ? amount1Delta : amount0Delta;
        if (inputDelta >= 0 || outputDelta <= 0) revert InvalidSwapDeltas(amount0Delta, amount1Delta);

        amountIn = SafeCast.toUint256(-int256(inputDelta));
        amountOut = SafeCast.toUint256(int256(outputDelta));
    }
}
