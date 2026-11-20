// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Identity and immutable swap parameters of a Uniswap V4 pool.
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// @notice Direction, signed amount, and price bound for a V4 pool swap.
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

/// @notice PoolManager methods required for V4 swaps and settlement.
interface IUniswapV4PoolManager {
    /// @notice Opens an unlock context and invokes the caller's unlock callback.
    function unlock(bytes calldata data) external returns (bytes memory result);

    /// @notice Swaps a pool inside an active unlock context.
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    )
        external
        returns (int256 swapDelta);

    /// @notice Selects an ERC-20 currency for the subsequent settlement.
    function sync(address currency) external;

    /// @notice Takes a positive currency delta from PoolManager.
    function take(address currency, address to, uint256 amount) external;

    /// @notice Settles a negative currency delta into PoolManager.
    function settle() external payable returns (uint256 paid);
}

/// @notice Callback invoked by PoolManager during unlock.
interface IUniswapV4UnlockCallback {
    /// @notice Completes swap and currency settlement inside PoolManager's unlock context.
    function unlockCallback(bytes calldata data) external returns (bytes memory result);
}
