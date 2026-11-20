// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IExecutor } from "../interfaces/IExecutor.sol";
import {
    ISovrynConverter,
    ISovrynConverterAnchor,
    ISovrynConverterRegistry,
    ISovrynSwapNetwork
} from "../interfaces/protocols/ISovryn.sol";

/// @notice Executes swaps through the canonical SovrynSwap network against registered V1 liquidity pools.
/// @dev Supports active two-token V1 converters with equal reserve weights. `data` is `abi.encode(converter)`.
contract SovrynExecutor is IExecutor {
    using SafeTransferLib for address;

    uint256 private constant FEE_DENOMINATOR = 1_000_000;
    uint32 private constant EQUAL_RESERVE_WEIGHT = 500_000;

    address public immutable NETWORK;
    address public immutable REGISTRY;

    error InvalidNetwork(address network);
    error InvalidRegistry(address registry);
    error InvalidPool(address pool);
    error InvalidSwapAmount(uint256 amount);
    error InvalidFee(uint32 feePips);
    error InsufficientLiquidity();
    error InputLimitExceeded(uint256 maximum, uint256 actual);

    constructor(address network_, address registry_) {
        if (network_ == address(0)) {
            revert InvalidNetwork(network_);
        }
        if (registry_ == address(0)) {
            revert InvalidRegistry(registry_);
        }
        NETWORK = network_;
        REGISTRY = registry_;
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
        (address anchor,,,) = _pool(data, tokenIn, tokenOut);
        amountOut = _convert(tokenIn, tokenOut, anchor, amountIn, 1);
        if (amountOut == 0) revert InsufficientLiquidity();
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
        (address anchor, uint256 reserveIn, uint256 reserveOut, uint32 feePips) = _pool(data, tokenIn, tokenOut);
        amountIn = _amountIn(amountOut, reserveIn, reserveOut, feePips);
        if (amountIn > amountInMaximum) revert InputLimitExceeded(amountInMaximum, amountIn);

        _convert(tokenIn, tokenOut, anchor, amountIn, amountOut);
    }

    function _pool(
        bytes calldata data,
        address tokenIn,
        address tokenOut
    )
        private
        view
        returns (address anchor, uint256 reserveIn, uint256 reserveOut, uint32 feePips)
    {
        address pool = abi.decode(data, (address));
        if (pool == address(0) || pool.code.length == 0) revert InvalidPool(pool);

        ISovrynConverter converter = ISovrynConverter(pool);
        anchor = converter.anchor();
        if (
            converter.converterType() != 1 || !converter.isActive() || converter.connectorTokenCount() != 2
                || anchor == address(0) || anchor.code.length == 0
                || !ISovrynConverterRegistry(REGISTRY).isLiquidityPool(anchor)
                || ISovrynConverterAnchor(anchor).owner() != pool
        ) {
            revert InvalidPool(pool);
        }

        feePips = converter.conversionFee();
        if (feePips >= FEE_DENOMINATOR) revert InvalidFee(feePips);

        address token0 = converter.connectorTokens(0);
        address token1 = converter.connectorTokens(1);
        if (!((tokenIn == token0 && tokenOut == token1) || (tokenIn == token1 && tokenOut == token0))) {
            revert InvalidPool(pool);
        }

        uint32 weightIn;
        uint32 weightOut;
        (reserveIn, weightIn,,,) = converter.connectors(tokenIn);
        (reserveOut, weightOut,,,) = converter.connectors(tokenOut);
        if (weightIn != EQUAL_RESERVE_WEIGHT || weightOut != EQUAL_RESERVE_WEIGHT) {
            revert InvalidPool(pool);
        }
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
    }

    function _convert(
        address tokenIn,
        address tokenOut,
        address anchor,
        uint256 amountIn,
        uint256 amountOutMinimum
    )
        private
        returns (uint256 amountOut)
    {
        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = anchor;
        path[2] = tokenOut;

        tokenIn.safeApproveWithRetry(NETWORK, amountIn);
        amountOut =
            ISovrynSwapNetwork(NETWORK).convertByPath(path, amountIn, amountOutMinimum, address(this), address(0), 0);
    }

    function _amountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint32 feePips
    )
        private
        pure
        returns (uint256 amountIn)
    {
        if (feePips >= FEE_DENOMINATOR) revert InvalidFee(feePips);

        uint256 grossAmountOut = Math.mulDiv(amountOut - 1, FEE_DENOMINATOR, FEE_DENOMINATOR - feePips) + 1;
        if (grossAmountOut >= reserveOut) revert InsufficientLiquidity();

        amountIn = Math.mulDiv(reserveIn, grossAmountOut, reserveOut - grossAmountOut, Math.Rounding.Ceil);
        if (amountIn == 0) revert InsufficientLiquidity();
    }
}
