// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { SovrynExecutor } from "../../src/executors/SovrynExecutor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockSovrynConverter, MockSovrynRegistry, MockSovrynSwapNetwork } from "../mocks/MockSovryn.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

contract SovrynExecutorTest is Test {
    uint256 private constant FEE_DENOMINATOR = 1_000_000;
    uint32 private constant FEE_PIPS = 3500;
    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);

    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockSovrynSwapNetwork private network;
    MockSovrynRegistry private registry;
    MockSovrynConverter private converter;
    SovrynExecutor private executor;
    MockPermit2 private permit2;
    SwapRouter private router;

    function setUp() public {
        tokenA = new MockERC20("Token A", "A");
        tokenB = new MockERC20("Token B", "B");
        network = new MockSovrynSwapNetwork();
        registry = new MockSovrynRegistry();
        converter = new MockSovrynConverter(address(network), address(tokenA), address(tokenB), FEE_PIPS);
        registry.setLiquidityPool(converter.ANCHOR(), true);
        executor = new SovrynExecutor(address(network), address(registry));
        permit2 = new MockPermit2();

        address[] memory executors = new address[](1);
        executors[0] = address(executor);
        router = new SwapRouter(address(this), address(new MockWrappedNative()), address(permit2), executors);

        tokenA.mint(address(converter), 100_000);
        tokenB.mint(address(converter), 200_000);
        tokenA.mint(USER, 10_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
    }

    function testExactInputUsesRegisteredV1Converter() public {
        uint256 amountIn = 1000;
        uint256 expectedOut = _amountOut(amountIn, 100_000, 200_000);

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: amountIn,
                amountOutMinimum: expectedOut,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactInputPaths(amountIn, address(converter))
            }),
            _permit(0)
        );

        assertEq(amountOut, expectedOut);
        assertEq(tokenB.balanceOf(RECIPIENT), expectedOut);
        assertEq(executor.NETWORK(), address(network));
        assertEq(executor.REGISTRY(), address(registry));
    }

    function testExactOutputUsesMinimalInputAndRefundsRemainder() public {
        uint256 amountOut = 1000;
        uint256 expectedIn = _amountIn(amountOut, 100_000, 200_000);
        uint256 expectedOut = _amountOut(expectedIn, 100_000, 200_000);
        uint256 balanceBefore = tokenA.balanceOf(USER);
        assertLt(_amountOut(expectedIn - 1, 100_000, 200_000), amountOut);

        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountOut: amountOut,
                amountInMaximum: expectedIn + 500,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactOutputPaths(amountOut, address(converter))
            }),
            _permit(0)
        );

        assertEq(amountIn, expectedIn);
        assertEq(balanceBefore - tokenA.balanceOf(USER), expectedIn);
        assertEq(tokenB.balanceOf(RECIPIENT), expectedOut);
    }

    function testRejectsConverterOutsideRegistry() public {
        MockSovrynConverter foreign =
            new MockSovrynConverter(address(network), address(tokenA), address(tokenB), FEE_PIPS);

        vm.expectRevert(abi.encodeWithSelector(SovrynExecutor.InvalidPool.selector, address(foreign)));
        vm.prank(USER);
        router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: 1000,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactInputPaths(1000, address(foreign))
            }),
            _permit(0)
        );
    }

    function testRejectsUnsupportedReserveWeights() public {
        converter.setWeights(600_000, 400_000);

        vm.expectRevert(abi.encodeWithSelector(SovrynExecutor.InvalidPool.selector, address(converter)));
        vm.prank(USER);
        router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: 1000,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactInputPaths(1000, address(converter))
            }),
            _permit(0)
        );
    }

    function testExactOutputHonorsInputMaximum() public {
        uint256 amountOut = 1000;
        uint256 expectedIn = _amountIn(amountOut, 100_000, 200_000);

        vm.expectRevert(abi.encodeWithSelector(SovrynExecutor.InputLimitExceeded.selector, expectedIn - 1, expectedIn));
        vm.prank(USER);
        router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountOut: amountOut,
                amountInMaximum: expectedIn - 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactOutputPaths(amountOut, address(converter))
            }),
            _permit(0)
        );
    }

    function testConstructorAcceptsAddressesBeforeDeployment() public {
        SovrynExecutor pending = new SovrynExecutor(address(0x1234), address(0x5678));
        assertEq(pending.NETWORK(), address(0x1234));
        assertEq(pending.REGISTRY(), address(0x5678));
    }

    function _exactInputPaths(
        uint256 amountIn,
        address pool
    )
        private
        view
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({
            executor: address(executor),
            tokenOut: address(tokenB),
            data: abi.encode(pool)
        });
        paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
    }

    function _exactOutputPaths(
        uint256 amountOut,
        address pool
    )
        private
        view
        returns (RouteTypes.ExactOutputPath[] memory paths)
    {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](1);
        steps[0] = RouteTypes.ExactOutputStep({
            executor: address(executor),
            tokenOut: address(tokenB),
            amountOut: amountOut,
            data: abi.encode(pool)
        });
        paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });
    }

    function _permit(uint48 nonce) private pure returns (ISwapRouter.Permit2Permit memory) {
        return ISwapRouter.Permit2Permit({ nonce: nonce, signature: hex"01" });
    }

    function _amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        uint256 grossAmountOut = amountIn * reserveOut / (reserveIn + amountIn);
        return grossAmountOut - grossAmountOut * FEE_PIPS / FEE_DENOMINATOR;
    }

    function _amountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        uint256 grossAmountOut = (amountOut - 1) * FEE_DENOMINATOR / (FEE_DENOMINATOR - FEE_PIPS) + 1;
        return (reserveIn * grossAmountOut + reserveOut - grossAmountOut - 1) / (reserveOut - grossAmountOut);
    }
}
