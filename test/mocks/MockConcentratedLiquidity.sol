// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAlgebraSwapCallback } from "../../src/interfaces/protocols/IAlgebra.sol";
import { IEnosysV3SwapCallback } from "../../src/interfaces/protocols/IEnosysV3.sol";
import { IUniswapV3SwapCallback } from "../../src/interfaces/protocols/IUniswapV3.sol";

contract MockV3Factory {
    mapping(bytes32 key => address pool) private pools;

    function setPool(address tokenA, address tokenB, uint24 fee, address pool) external {
        pools[_key(tokenA, tokenB, fee)] = pool;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address) {
        return pools[_key(tokenA, tokenB, fee)];
    }

    function _key(address tokenA, address tokenB, uint24 fee) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1, fee));
    }
}

contract MockSlipstreamFactory {
    mapping(bytes32 key => address pool) private pools;

    function setPool(address tokenA, address tokenB, int24 tickSpacing, address pool) external {
        pools[_key(tokenA, tokenB, tickSpacing)] = pool;
    }

    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address) {
        return pools[_key(tokenA, tokenB, tickSpacing)];
    }

    function _key(address tokenA, address tokenB, int24 tickSpacing) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1, tickSpacing));
    }
}

contract MockAlgebraFactory {
    mapping(bytes32 key => address pool) private pools;
    mapping(bytes32 key => address pool) private customPools;

    function setPool(address tokenA, address tokenB, address pool) external {
        pools[_key(tokenA, tokenB)] = pool;
    }

    function setCustomPool(address deployer, address tokenA, address tokenB, address pool) external {
        customPools[keccak256(abi.encode(deployer, _key(tokenA, tokenB)))] = pool;
    }

    function poolByPair(address tokenA, address tokenB) external view returns (address) {
        return pools[_key(tokenA, tokenB)];
    }

    function customPoolByPair(address deployer, address tokenA, address tokenB) external view returns (address) {
        return customPools[keccak256(abi.encode(deployer, _key(tokenA, tokenB)))];
    }

    function _key(address tokenA, address tokenB) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }
}

abstract contract MockConcentratedPool {
    using SafeERC20 for IERC20;

    address private immutable TOKEN0;
    address private immutable TOKEN1;

    constructor(address tokenA, address tokenB) {
        (TOKEN0, TOKEN1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function token0() external view returns (address) {
        return TOKEN0;
    }

    function token1() external view returns (address) {
        return TOKEN1;
    }

    function _amounts(bool zeroForOne, int256 amountSpecified) internal pure returns (int256 amount0, int256 amount1) {
        bool exactInput = amountSpecified > 0;
        uint256 specified = uint256(exactInput ? amountSpecified : -amountSpecified);
        uint256 amountIn = exactInput ? specified : (specified + 1) / 2;
        uint256 amountOut = exactInput ? specified * 2 : specified;
        int256 signedAmountIn = SafeCast.toInt256(amountIn);
        int256 signedAmountOut = SafeCast.toInt256(amountOut);
        (amount0, amount1) = zeroForOne ? (signedAmountIn, -signedAmountOut) : (-signedAmountOut, signedAmountIn);
    }

    function _sendOutput(address recipient, int256 amount0, int256 amount1) internal {
        if (amount0 < 0) IERC20(TOKEN0).safeTransfer(recipient, SafeCast.toUint256(-amount0));
        if (amount1 < 0) IERC20(TOKEN1).safeTransfer(recipient, SafeCast.toUint256(-amount1));
    }
}

contract MockV3Pool is MockConcentratedPool {
    constructor(address tokenA, address tokenB) MockConcentratedPool(tokenA, tokenB) { }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1)
    {
        (amount0, amount1) = _amounts(zeroForOne, amountSpecified);
        _sendOutput(recipient, amount0, amount1);
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
    }
}

contract MockEnosysV3Pool is MockConcentratedPool {
    constructor(address tokenA, address tokenB) MockConcentratedPool(tokenA, tokenB) { }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1)
    {
        (amount0, amount1) = _amounts(zeroForOne, amountSpecified);
        _sendOutput(recipient, amount0, amount1);
        IEnosysV3SwapCallback(msg.sender).enosysdexV3SwapCallback(amount0, amount1, data);
    }
}

contract MockAlgebraPool is MockConcentratedPool {
    constructor(address tokenA, address tokenB) MockConcentratedPool(tokenA, tokenB) { }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata data
    )
        external
        returns (int256 amount0, int256 amount1)
    {
        (amount0, amount1) = _amounts(zeroForOne, amountSpecified);
        _sendOutput(recipient, amount0, amount1);
        IAlgebraSwapCallback(msg.sender).algebraSwapCallback(amount0, amount1, data);
    }
}
