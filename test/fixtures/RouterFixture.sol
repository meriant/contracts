// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { MockCallbackExecutor } from "../mocks/MockCallbackExecutor.sol";
import { MockCallbackPool } from "../mocks/MockCallbackPool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockExecutor } from "../mocks/MockExecutor.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

/// @notice Shared mock router setup and route builders for behavior and gas tests.
abstract contract RouterFixture is Test {
    uint48 internal constant DEADLINE = 2_000_000_000;

    address internal constant USER = address(0xA11CE);
    address internal constant RECIPIENT = address(0xB0B);

    SwapRouter internal router;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    MockWrappedNative internal wrappedNative;
    MockExecutor internal executorA;
    MockExecutor internal executorB;
    MockCallbackPool internal callbackPool;
    MockCallbackExecutor internal callbackExecutor;
    MockPermit2 internal permit2;

    function setUp() public virtual {
        tokenA = new MockERC20("Token A", "A");
        tokenB = new MockERC20("Token B", "B");
        tokenC = new MockERC20("Token C", "C");
        wrappedNative = new MockWrappedNative();
        executorA = new MockExecutor();
        executorB = new MockExecutor();
        callbackPool = new MockCallbackPool();
        callbackExecutor = new MockCallbackExecutor(address(callbackPool));
        permit2 = new MockPermit2();

        address[] memory executors = new address[](3);
        executors[0] = address(executorA);
        executors[1] = address(executorB);
        executors[2] = address(callbackExecutor);
        router = new SwapRouter(address(this), address(wrappedNative), address(permit2), executors);

        tokenA.mint(USER, 10_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
        vm.deal(USER, 10_000);
        vm.deal(address(wrappedNative), 10_000);
    }

    function _permit() internal pure returns (ISwapRouter.Permit2Permit memory) {
        return ISwapRouter.Permit2Permit({ nonce: 0, signature: hex"01" });
    }

    function _emptyPermit() internal pure returns (ISwapRouter.Permit2Permit memory) {
        return ISwapRouter.Permit2Permit({ nonce: 0, signature: "" });
    }

    function _inputParams(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        RouteTypes.ExactInputPath[] memory paths
    )
        internal
        pure
        returns (RouteTypes.ExactInputParams memory)
    {
        return RouteTypes.ExactInputParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            recipient: RECIPIENT,
            deadline: DEADLINE,
            paths: paths
        });
    }

    function _outputParams(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        RouteTypes.ExactOutputPath[] memory paths
    )
        internal
        pure
        returns (RouteTypes.ExactOutputParams memory)
    {
        return RouteTypes.ExactOutputParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            recipient: RECIPIENT,
            deadline: DEADLINE,
            paths: paths
        });
    }

    function _singleExactInputPath(
        uint256 amountIn,
        RouteTypes.ExactInputStep memory step
    )
        internal
        pure
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = _exactInputPath(amountIn, step);
    }

    function _singleExactOutputPath(RouteTypes.ExactOutputStep memory step)
        internal
        pure
        returns (RouteTypes.ExactOutputPath[] memory paths)
    {
        paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = _exactOutputPath(step);
    }

    function _exactInputPath(
        uint256 amountIn,
        RouteTypes.ExactInputStep memory step
    )
        internal
        pure
        returns (RouteTypes.ExactInputPath memory path)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = step;
        path = RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
    }

    function _exactOutputPath(RouteTypes.ExactOutputStep memory step)
        internal
        pure
        returns (RouteTypes.ExactOutputPath memory path)
    {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](1);
        steps[0] = step;
        path = RouteTypes.ExactOutputPath({ steps: steps });
    }

    function _inputStep(
        address executor,
        address tokenOut,
        uint256 numerator,
        uint256 denominator
    )
        internal
        pure
        returns (RouteTypes.ExactInputStep memory)
    {
        return
            RouteTypes.ExactInputStep({
                executor: executor,
                tokenOut: tokenOut,
                data: abi.encode(numerator, denominator)
            });
    }

    function _outputStep(
        address executor,
        address tokenOut,
        uint256 amountOut,
        uint256 numerator,
        uint256 denominator
    )
        internal
        pure
        returns (RouteTypes.ExactOutputStep memory)
    {
        return RouteTypes.ExactOutputStep({
            executor: executor,
            tokenOut: tokenOut,
            amountOut: amountOut,
            data: abi.encode(numerator, denominator)
        });
    }

    function _assertRouterBalancesAreZero() internal view {
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenB.balanceOf(address(router)), 0);
        assertEq(tokenC.balanceOf(address(router)), 0);
        assertEq(wrappedNative.balanceOf(address(router)), 0);
    }
}
