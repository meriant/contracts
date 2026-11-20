// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

/// @notice Sovryn network method used to convert along a registered path.
interface ISovrynSwapNetwork {
    /// @notice Executes a conversion and sends output to the beneficiary.
    function convertByPath(
        address[] calldata path,
        uint256 amount,
        uint256 minReturn,
        address beneficiary,
        address affiliateAccount,
        uint256 affiliateFee
    )
        external
        payable
        returns (uint256 amountOut);
}

/// @notice Sovryn registry method used to authenticate a liquidity-pool anchor.
interface ISovrynConverterRegistry {
    /// @notice Returns whether an anchor represents a registered liquidity pool.
    function isLiquidityPool(address anchor) external view returns (bool);
}

/// @notice Pool anchor method used to resolve the current converter.
interface ISovrynConverterAnchor {
    /// @notice Returns the converter that owns the anchor.
    function owner() external view returns (address);
}

/// @notice Type-1 converter methods used for validation and pricing.
interface ISovrynConverter {
    /// @notice Returns the converter's anchor.
    function anchor() external view returns (address);

    /// @notice Returns the converter implementation type.
    function converterType() external view returns (uint16);

    /// @notice Returns whether the converter is active.
    function isActive() external view returns (bool);

    /// @notice Returns the number of connector tokens.
    function connectorTokenCount() external view returns (uint16);

    /// @notice Returns a connector token by index.
    function connectorTokens(uint256 index) external view returns (address);

    /// @notice Returns the connector's balance, weight, and configuration flags.
    function connectors(address token) external view returns (uint256 balance, uint32 weight, bool, bool, bool);

    /// @notice Returns the converter's current fee.
    function conversionFee() external view returns (uint32);

    /// @notice Quotes output and fee for a source, target, and amount.
    function targetAmountAndFee(
        address sourceToken,
        address targetToken,
        uint256 amount
    )
        external
        view
        returns (uint256 amountOut, uint256 fee);
}
