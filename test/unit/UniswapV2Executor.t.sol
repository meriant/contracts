// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { UniswapV2Executor } from "../../src/executors/UniswapV2Executor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockUniswapV2Factory, MockUniswapV2Pair } from "../mocks/MockUniswapV2.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

contract UniswapV2ExecutorTest is Test {
    uint32 private constant STANDARD_FEE_PIPS = 3000;
    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);

    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockERC20 private tokenC;
    MockUniswapV2Factory private factory;
    MockUniswapV2Pair private pair;
    UniswapV2Executor private executor;
    MockPermit2 private permit2;
    SwapRouter private router;

    function setUp() public {
        tokenA = new MockERC20("Token A", "A");
        tokenB = new MockERC20("Token B", "B");
        tokenC = new MockERC20("Token C", "C");
        factory = new MockUniswapV2Factory();
        pair = new MockUniswapV2Pair(address(tokenA), address(tokenB));
        factory.setPair(address(tokenA), address(tokenB), address(pair));
        executor = new UniswapV2Executor(address(factory), STANDARD_FEE_PIPS);
        permit2 = new MockPermit2();

        address[] memory executors = new address[](1);
        executors[0] = address(executor);
        router = new SwapRouter(address(this), address(new MockWrappedNative()), address(permit2), executors);

        tokenA.mint(address(pair), 100_000);
        tokenB.mint(address(pair), 200_000);
        pair.sync();
        tokenA.mint(USER, 10_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
    }

    function testExactInputUsesStandardV2Math() public {
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
                paths: _exactInputPaths(amountIn, address(pair))
            }),
            _permit(0)
        );

        assertEq(amountOut, expectedOut);
        assertEq(tokenB.balanceOf(RECIPIENT), expectedOut);
        assertEq(executor.FACTORY(), address(factory));
        assertEq(executor.FEE_PIPS(), STANDARD_FEE_PIPS);
    }

    function testExactOutputUsesStandardV2MathAndRefundsRemainder() public {
        uint256 amountOut = 1000;
        uint256 expectedIn = _amountIn(amountOut, 100_000, 200_000);
        uint256 balanceBefore = tokenA.balanceOf(USER);

        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountOut: amountOut,
                amountInMaximum: expectedIn + 500,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactOutputPaths(amountOut, address(pair))
            }),
            _permit(0)
        );

        assertEq(amountIn, expectedIn);
        assertEq(balanceBefore - tokenA.balanceOf(USER), expectedIn);
        assertEq(tokenB.balanceOf(RECIPIENT), amountOut);
    }

    function testRejectsPairOutsideConfiguredFactory() public {
        MockUniswapV2Pair foreignPair = new MockUniswapV2Pair(address(tokenA), address(tokenC));
        tokenA.mint(address(foreignPair), 100_000);
        tokenC.mint(address(foreignPair), 100_000);
        foreignPair.sync();

        vm.expectRevert(abi.encodeWithSelector(UniswapV2Executor.InvalidPool.selector, address(foreignPair)));
        vm.prank(USER);
        router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenC),
                amountIn: 1000,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactInputPathsFor(address(tokenA), address(tokenC), 1000, address(foreignPair))
            }),
            _permit(0)
        );
    }

    function testExactOutputHonorsInputMaximum() public {
        uint256 amountOut = 1000;
        uint256 expectedIn = _amountIn(amountOut, 100_000, 200_000);

        vm.expectRevert(
            abi.encodeWithSelector(UniswapV2Executor.InputLimitExceeded.selector, expectedIn - 1, expectedIn)
        );
        vm.prank(USER);
        router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountOut: amountOut,
                amountInMaximum: expectedIn - 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactOutputPaths(amountOut, address(pair))
            }),
            _permit(0)
        );
    }

    function testConstructorAcceptsFactoryAddressBeforeDeployment() public {
        UniswapV2Executor pending = new UniswapV2Executor(address(0x1234), STANDARD_FEE_PIPS);
        assertEq(pending.FACTORY(), address(0x1234));
    }

    function testSupportsProtocolSpecificFee() public {
        uint32 feePips = 2000;
        UniswapV2Executor feeExecutor = new UniswapV2Executor(address(factory), feePips);
        address[] memory executors = new address[](1);
        executors[0] = address(feeExecutor);
        SwapRouter feeRouter =
            new SwapRouter(address(this), address(new MockWrappedNative()), address(permit2), executors);

        uint256 amountIn = 1000;
        uint256 expectedOut = _amountOut(amountIn, 100_000, 200_000, feePips);
        vm.prank(USER);
        uint256 amountOut = feeRouter.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: amountIn,
                amountOutMinimum: expectedOut,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactInputPathsForExecutor(amountIn, address(pair), address(feeExecutor))
            }),
            _permit(0)
        );

        assertEq(amountOut, expectedOut);
        assertEq(feeExecutor.FEE_PIPS(), feePips);
    }

    function testConstructorRejectsInvalidFee() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapV2Executor.InvalidFee.selector, 0));
        new UniswapV2Executor(address(factory), 0);

        vm.expectRevert(abi.encodeWithSelector(UniswapV2Executor.InvalidFee.selector, 1_000_000));
        new UniswapV2Executor(address(factory), 1_000_000);
    }

    function _exactInputPaths(
        uint256 amountIn,
        address pool
    )
        private
        view
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        return _exactInputPathsFor(address(tokenA), address(tokenB), amountIn, pool);
    }

    function _exactInputPathsForExecutor(
        uint256 amountIn,
        address pool,
        address executorAddress
    )
        private
        view
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] =
            RouteTypes.ExactInputStep({ executor: executorAddress, tokenOut: address(tokenB), data: abi.encode(pool) });
        paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
    }

    function _exactInputPathsFor(
        address,
        address tokenOut,
        uint256 amountIn,
        address pool
    )
        private
        view
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] =
            RouteTypes.ExactInputStep({ executor: address(executor), tokenOut: tokenOut, data: abi.encode(pool) });
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
        return _amountOut(amountIn, reserveIn, reserveOut, STANDARD_FEE_PIPS);
    }

    function _amountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint32 feePips
    )
        private
        pure
        returns (uint256)
    {
        uint256 amountInWithFee = amountIn * (1_000_000 - feePips);
        return amountInWithFee * reserveOut / (reserveIn * 1_000_000 + amountInWithFee);
    }

    function _amountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        return reserveIn * amountOut * 1_000_000 / ((reserveOut - amountOut) * (1_000_000 - STANDARD_FEE_PIPS)) + 1;
    }
}
