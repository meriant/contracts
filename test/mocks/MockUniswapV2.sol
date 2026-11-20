// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Factory, IUniswapV2Pair } from "../../src/interfaces/protocols/IUniswapV2.sol";

contract MockUniswapV2Factory is IUniswapV2Factory {
    mapping(address tokenA => mapping(address tokenB => address pair)) public pairs;

    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }

    function getPair(address tokenA, address tokenB) external view override returns (address pair) {
        return pairs[tokenA][tokenB];
    }
}

contract MockUniswapV2Pair is IUniswapV2Pair {
    using SafeERC20 for IERC20;

    address public immutable TOKEN0;
    address public immutable TOKEN1;

    uint112 private reserve0;
    uint112 private reserve1;

    constructor(address token0_, address token1_) {
        TOKEN0 = token0_;
        TOKEN1 = token1_;
    }

    function token0() external view override returns (address) {
        return TOKEN0;
    }

    function token1() external view override returns (address) {
        return TOKEN1;
    }

    function sync() external {
        _sync();
    }

    function getReserves() external view override returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata) external override {
        if (amount0Out > 0) IERC20(TOKEN0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(TOKEN1).safeTransfer(to, amount1Out);
        _sync();
    }

    function _sync() private {
        reserve0 = uint112(IERC20(TOKEN0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(TOKEN1).balanceOf(address(this)));
    }
}
