// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IExecutor } from "../interfaces/IExecutor.sol";
import { IUniswapV2Factory, IUniswapV2Pair } from "../interfaces/protocols/IUniswapV2.sol";

/// @notice Executes swaps against one factory of Uniswap V2-compatible pairs with a fixed fee.
/// @dev Deploy one immutable instance per factory and fee. `data` is `abi.encode(pair)`.
contract UniswapV2Executor is IExecutor {
    using SafeTransferLib for address;

    uint256 private constant FEE_DENOMINATOR = 1_000_000;

    address public immutable FACTORY;
    uint32 public immutable FEE_PIPS;
    uint256 private immutable FEE_MULTIPLIER;

    error InvalidFactory(address factory);
    error InvalidFee(uint32 feePips);
    error InvalidPool(address pool);
    error InvalidSwapAmount(uint256 amount);
    error InsufficientLiquidity();
    error InputLimitExceeded(uint256 maximum, uint256 actual);

    constructor(address factory_, uint32 feePips_) {
        if (factory_ == address(0)) revert InvalidFactory(factory_);
        if (feePips_ == 0 || feePips_ >= FEE_DENOMINATOR) revert InvalidFee(feePips_);
        FACTORY = factory_;
        FEE_PIPS = feePips_;
        FEE_MULTIPLIER = FEE_DENOMINATOR - feePips_;
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
        if (amountIn == 0) revert InvalidSwapAmount(amountIn);
        (IUniswapV2Pair pair, bool zeroForOne, uint256 reserveIn, uint256 reserveOut) = _pool(data, tokenIn, tokenOut);

        uint256 reserveInScaled = reserveIn * FEE_DENOMINATOR;
        if (amountIn > (type(uint256).max - reserveInScaled) / FEE_MULTIPLIER) {
            revert InvalidSwapAmount(amountIn);
        }
        uint256 amountInWithFee = amountIn * FEE_MULTIPLIER;
        amountOut = Math.mulDiv(amountInWithFee, reserveOut, reserveInScaled + amountInWithFee);
        if (amountOut == 0) revert InsufficientLiquidity();

        tokenIn.safeTransfer(address(pair), amountIn);
        _swap(pair, zeroForOne, amountOut);
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
        if (amountOut == 0) revert InvalidSwapAmount(amountOut);
        (IUniswapV2Pair pair, bool zeroForOne, uint256 reserveIn, uint256 reserveOut) = _pool(data, tokenIn, tokenOut);
        if (amountOut >= reserveOut) revert InsufficientLiquidity();

        amountIn = Math.mulDiv(reserveIn, amountOut * FEE_DENOMINATOR, (reserveOut - amountOut) * FEE_MULTIPLIER) + 1;
        if (amountIn > amountInMaximum) revert InputLimitExceeded(amountInMaximum, amountIn);

        tokenIn.safeTransfer(address(pair), amountIn);
        _swap(pair, zeroForOne, amountOut);
    }

    function _pool(
        bytes calldata data,
        address tokenIn,
        address tokenOut
    )
        private
        view
        returns (IUniswapV2Pair pair, bool zeroForOne, uint256 reserveIn, uint256 reserveOut)
    {
        address pairAddress = abi.decode(data, (address));
        if (pairAddress == address(0) || IUniswapV2Factory(FACTORY).getPair(tokenIn, tokenOut) != pairAddress) {
            revert InvalidPool(pairAddress);
        }

        pair = IUniswapV2Pair(pairAddress);
        address token0 = pair.token0();
        address token1 = pair.token1();
        if (tokenIn == token0 && tokenOut == token1) {
            zeroForOne = true;
        } else if (tokenIn != token1 || tokenOut != token0) {
            revert InvalidPool(pairAddress);
        }

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        (reserveIn, reserveOut) = zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
    }

    function _swap(IUniswapV2Pair pair, bool zeroForOne, uint256 amountOut) private {
        pair.swap(zeroForOne ? 0 : amountOut, zeroForOne ? amountOut : 0, address(this), "");
    }
}
