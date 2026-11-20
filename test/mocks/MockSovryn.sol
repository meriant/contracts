// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    ISovrynConverter,
    ISovrynConverterAnchor,
    ISovrynConverterRegistry,
    ISovrynSwapNetwork
} from "../../src/interfaces/protocols/ISovryn.sol";

contract MockSovrynAnchor is ISovrynConverterAnchor {
    address public override owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function setOwner(address owner_) external {
        owner = owner_;
    }
}

    contract MockSovrynRegistry is ISovrynConverterRegistry {
        mapping(address anchor => bool registered) public liquidityPools;

        function setLiquidityPool(address anchor, bool registered) external {
            liquidityPools[anchor] = registered;
        }

        function isLiquidityPool(address anchor) external view override returns (bool) {
            return liquidityPools[anchor];
        }
    }

    contract MockSovrynConverter is ISovrynConverter {
        using SafeERC20 for IERC20;

        uint256 private constant FEE_DENOMINATOR = 1_000_000;

        address public immutable NETWORK;
        address public immutable TOKEN0;
        address public immutable TOKEN1;
        address public immutable ANCHOR;

        uint32 public override conversionFee;
        uint32 public weight0 = 500_000;
        uint32 public weight1 = 500_000;
        bool public active = true;

        error InvalidConnector(uint256 index);
        error InvalidNetwork(address caller);

        constructor(address network_, address token0_, address token1_, uint32 conversionFee_) {
            NETWORK = network_;
            TOKEN0 = token0_;
            TOKEN1 = token1_;
            conversionFee = conversionFee_;
            ANCHOR = address(new MockSovrynAnchor(address(this)));
        }

        function anchor() external view override returns (address) {
            return ANCHOR;
        }

        function converterType() external pure override returns (uint16) {
            return 1;
        }

        function isActive() external view override returns (bool) {
            return active;
        }

        function connectorTokenCount() external pure override returns (uint16) {
            return 2;
        }

        function connectorTokens(uint256 index) external view override returns (address) {
            if (index == 0) return TOKEN0;
            if (index == 1) return TOKEN1;
            revert InvalidConnector(index);
        }

        function connectors(address token)
            external
            view
            override
            returns (uint256 balance, uint32 weight, bool, bool, bool)
        {
            if (token == TOKEN0) return (IERC20(TOKEN0).balanceOf(address(this)), weight0, false, true, false);
            if (token == TOKEN1) return (IERC20(TOKEN1).balanceOf(address(this)), weight1, false, true, false);
            return (0, 0, false, false, false);
        }

        function targetAmountAndFee(
            address sourceToken,
            address targetToken,
            uint256 amount
        )
            external
            view
            override
            returns (uint256 amountOut, uint256 fee)
        {
            uint256 reserveIn = IERC20(sourceToken).balanceOf(address(this));
            uint256 reserveOut = IERC20(targetToken).balanceOf(address(this));
            uint256 grossAmountOut = amount * reserveOut / (reserveIn + amount);
            fee = grossAmountOut * conversionFee / FEE_DENOMINATOR;
            amountOut = grossAmountOut - fee;
        }

        function release(address token, address beneficiary, uint256 amount) external {
            if (msg.sender != NETWORK) revert InvalidNetwork(msg.sender);
            IERC20(token).safeTransfer(beneficiary, amount);
        }

        function setWeights(uint32 weight0_, uint32 weight1_) external {
            weight0 = weight0_;
            weight1 = weight1_;
        }
    }

        contract MockSovrynSwapNetwork is ISovrynSwapNetwork {
            using SafeERC20 for IERC20;

            error InvalidPath();
            error InvalidAffiliate();
            error ReturnTooLow(uint256 minimum, uint256 actual);

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
                override
                returns (uint256 amountOut)
            {
                if (path.length != 3) revert InvalidPath();
                if (affiliateAccount != address(0) || affiliateFee != 0) revert InvalidAffiliate();

                MockSovrynConverter converter = MockSovrynConverter(ISovrynConverterAnchor(path[1]).owner());
                (amountOut,) = converter.targetAmountAndFee(path[0], path[2], amount);
                if (amountOut < minReturn) revert ReturnTooLow(minReturn, amountOut);

                IERC20(path[0]).safeTransferFrom(msg.sender, address(converter), amount);
                converter.release(path[2], beneficiary == address(0) ? msg.sender : beneficiary, amountOut);
            }
        }
