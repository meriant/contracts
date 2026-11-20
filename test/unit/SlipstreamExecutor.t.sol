// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { SlipstreamExecutor } from "../../src/executors/SlipstreamExecutor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { MockSlipstreamFactory, MockV3Pool } from "../mocks/MockConcentratedLiquidity.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

contract SlipstreamExecutorTest is Test {
    int24 private constant TICK_SPACING = 100;
    uint24 private constant TICK_SPACING_PARAMETER = 100;
    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);

    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockV3Pool private pool;
    MockPermit2 private permit2;
    SlipstreamExecutor private executor;
    SwapRouter private router;

    function setUp() public {
        tokenA = new MockERC20("Token A", "A");
        tokenB = new MockERC20("Token B", "B");
        pool = new MockV3Pool(address(tokenA), address(tokenB));
        MockSlipstreamFactory factory = new MockSlipstreamFactory();
        factory.setPool(address(tokenA), address(tokenB), TICK_SPACING, address(pool));

        executor = new SlipstreamExecutor(address(factory));
        permit2 = new MockPermit2();
        address[] memory executors = new address[](1);
        executors[0] = address(executor);
        router = new SwapRouter(address(this), address(new MockWrappedNative()), address(permit2), executors);

        tokenA.mint(USER, 1000);
        tokenB.mint(address(pool), 10_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
    }

    function testSwapUsesTickSpacingPoolLookup() public {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({
            executor: address(executor),
            tokenOut: address(tokenB),
            data: abi.encode(address(pool), TICK_SPACING_PARAMETER, uint160(0))
        });
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 50, steps: steps });

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: 50,
                amountOutMinimum: 100,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            ISwapRouter.Permit2Permit({ nonce: 0, signature: hex"01" })
        );

        assertEq(amountOut, 100);
        assertEq(tokenB.balanceOf(RECIPIENT), 100);
    }
}
