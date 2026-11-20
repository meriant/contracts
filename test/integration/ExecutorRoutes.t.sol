// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { AlgebraExecutor } from "../../src/executors/AlgebraExecutor.sol";
import { EnosysV3Executor } from "../../src/executors/EnosysV3Executor.sol";
import { UniswapV3Executor } from "../../src/executors/UniswapV3Executor.sol";
import { V3ExecutorBase } from "../../src/executors/V3ExecutorBase.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import {
    MockAlgebraFactory,
    MockAlgebraPool,
    MockEnosysV3Pool,
    MockV3Factory,
    MockV3Pool
} from "../mocks/MockConcentratedLiquidity.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

/// @notice End-to-end mock routes across different protocol executors.
contract ExecutorRoutesTest is Test {
    uint24 private constant FEE = 3000;
    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);
    address private constant CUSTOM_DEPLOYER = address(0xCAFE);

    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockERC20 private tokenC;
    MockV3Factory private sparkFactory;
    MockV3Factory private enosysFactory;
    MockAlgebraFactory private algebraFactory;
    MockV3Pool private sparkPool;
    MockEnosysV3Pool private enosysPool;
    MockAlgebraPool private algebraPool;
    UniswapV3Executor private sparkExecutor;
    EnosysV3Executor private enosysExecutor;
    AlgebraExecutor private algebraExecutor;
    SwapRouter private router;
    MockPermit2 private permit2;

    function setUp() public {
        tokenA = new MockERC20("Token A", "A");
        tokenB = new MockERC20("Token B", "B");
        tokenC = new MockERC20("Token C", "C");
        sparkFactory = new MockV3Factory();
        enosysFactory = new MockV3Factory();
        algebraFactory = new MockAlgebraFactory();

        sparkPool = new MockV3Pool(address(tokenA), address(tokenB));
        enosysPool = new MockEnosysV3Pool(address(tokenA), address(tokenC));
        algebraPool = new MockAlgebraPool(address(tokenB), address(tokenC));
        sparkFactory.setPool(address(tokenA), address(tokenB), FEE, address(sparkPool));
        enosysFactory.setPool(address(tokenA), address(tokenC), FEE, address(enosysPool));
        algebraFactory.setCustomPool(CUSTOM_DEPLOYER, address(tokenB), address(tokenC), address(algebraPool));

        sparkExecutor = new UniswapV3Executor(address(sparkFactory));
        enosysExecutor = new EnosysV3Executor(address(enosysFactory));
        algebraExecutor = new AlgebraExecutor(address(algebraFactory));
        permit2 = new MockPermit2();

        address[] memory executors = new address[](3);
        executors[0] = address(sparkExecutor);
        executors[1] = address(enosysExecutor);
        executors[2] = address(algebraExecutor);
        router = new SwapRouter(address(this), address(new MockWrappedNative()), address(permit2), executors);

        tokenA.mint(USER, 10_000);
        tokenA.mint(address(sparkPool), 100_000);
        tokenB.mint(address(sparkPool), 100_000);
        tokenA.mint(address(enosysPool), 100_000);
        tokenC.mint(address(enosysPool), 100_000);
        tokenB.mint(address(algebraPool), 100_000);
        tokenC.mint(address(algebraPool), 100_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
    }

    function testV3ExecutorWorksForSparkAndEnosysFactories() public {
        RouteTypes.ExactInputPath memory sparkPath = _inputPath(
            40, _inputStep(address(sparkExecutor), address(tokenA), address(tokenB), _v3Data(address(sparkPool)))
        );
        RouteTypes.ExactInputPath memory enosysPath = _inputPath(
            60, _inputStep(address(enosysExecutor), address(tokenA), address(tokenC), _v3Data(address(enosysPool)))
        );

        vm.prank(USER);
        uint256 sparkAmountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: 40,
                amountOutMinimum: 80,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _only(sparkPath)
            }),
            _permit(0)
        );
        vm.prank(USER);
        uint256 enosysAmountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenC),
                amountIn: 60,
                amountOutMinimum: 120,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _only(enosysPath)
            }),
            _permit(1)
        );

        assertEq(sparkAmountOut, 80);
        assertEq(enosysAmountOut, 120);
        assertEq(tokenB.balanceOf(RECIPIENT), 80);
        assertEq(tokenC.balanceOf(RECIPIENT), 120);
        assertEq(sparkExecutor.FACTORY(), address(sparkFactory));
        assertEq(enosysExecutor.FACTORY(), address(enosysFactory));
    }

    function testMixedV3AndAlgebraExactInput() public {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](2);
        steps[0] = _inputStep(address(sparkExecutor), address(tokenA), address(tokenB), _v3Data(address(sparkPool)));
        steps[1] = _inputStep(
            address(algebraExecutor), address(tokenB), address(tokenC), _algebraData(address(algebraPool))
        );
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 25, steps: steps });

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenC),
                amountIn: 25,
                amountOutMinimum: 100,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _permit(0)
        );

        assertEq(amountOut, 100);
        assertEq(tokenC.balanceOf(RECIPIENT), 100);
    }

    function testMixedV3AndAlgebraExactOutputUsesEveryHopTarget() public {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](2);
        steps[0] =
            _outputStep(address(sparkExecutor), address(tokenA), address(tokenB), 50, _v3Data(address(sparkPool)));
        steps[1] = _outputStep(
            address(algebraExecutor), address(tokenB), address(tokenC), 100, _algebraData(address(algebraPool))
        );
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });

        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenC),
                amountOut: 100,
                amountInMaximum: 30,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _permit(0)
        );

        assertEq(amountIn, 25);
        assertEq(tokenA.balanceOf(USER), 9975);
        assertEq(tokenC.balanceOf(RECIPIENT), 100);
    }

    function testExecutorsRejectPoolsOutsideTheirFactory() public {
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = _inputPath(
            25, _inputStep(address(sparkExecutor), address(tokenA), address(tokenC), _v3Data(address(enosysPool)))
        );

        vm.expectRevert(abi.encodeWithSelector(V3ExecutorBase.InvalidPool.selector, address(enosysPool)));
        vm.prank(USER);
        router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenC),
                amountIn: 25,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _permit(0)
        );
    }

    function testCallbacksRejectUnverifiedCallers() public {
        vm.expectRevert(abi.encodeWithSelector(V3ExecutorBase.InvalidSwapCallback.selector, address(this)));
        sparkExecutor.uniswapV3SwapCallback(1, -1, abi.encode(address(tokenA), address(tokenB), FEE));

        vm.expectRevert(abi.encodeWithSelector(V3ExecutorBase.InvalidSwapCallback.selector, address(this)));
        enosysExecutor.enosysdexV3SwapCallback(1, -1, abi.encode(address(tokenA), address(tokenC), FEE));

        vm.expectRevert(abi.encodeWithSelector(AlgebraExecutor.InvalidSwapCallback.selector, address(this)));
        algebraExecutor.algebraSwapCallback(1, -1, abi.encode(CUSTOM_DEPLOYER, address(tokenB), address(tokenC)));
    }

    function _inputStep(
        address executor,
        address,
        address tokenOut,
        bytes memory data
    )
        private
        pure
        returns (RouteTypes.ExactInputStep memory)
    {
        return RouteTypes.ExactInputStep({ executor: executor, tokenOut: tokenOut, data: data });
    }

    function _permit(uint48 nonce) private pure returns (ISwapRouter.Permit2Permit memory) {
        return ISwapRouter.Permit2Permit({ nonce: nonce, signature: hex"01" });
    }

    function _outputStep(
        address executor,
        address,
        address tokenOut,
        uint256 amountOut,
        bytes memory data
    )
        private
        pure
        returns (RouteTypes.ExactOutputStep memory)
    {
        return RouteTypes.ExactOutputStep({ executor: executor, tokenOut: tokenOut, amountOut: amountOut, data: data });
    }

    function _inputPath(
        uint256 amountIn,
        RouteTypes.ExactInputStep memory step
    )
        private
        pure
        returns (RouteTypes.ExactInputPath memory)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = step;
        return RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
    }

    function _only(RouteTypes.ExactInputPath memory path)
        private
        pure
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = path;
    }

    function _v3Data(address pool) private pure returns (bytes memory) {
        return abi.encode(pool, FEE, uint160(0));
    }

    function _algebraData(address pool) private pure returns (bytes memory) {
        return abi.encode(pool, CUSTOM_DEPLOYER, uint160(0));
    }
}
