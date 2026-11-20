// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { UniswapV4Executor } from "../../src/executors/UniswapV4Executor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { PoolKey } from "../../src/interfaces/protocols/IUniswapV4.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockUniswapV4PoolManager } from "../mocks/MockUniswapV4.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

contract UniswapV4ExecutorTest is Test {
    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);
    uint24 private constant FEE = 3000;
    int24 private constant TICK_SPACING = 60;

    MockERC20 private tokenA;
    MockERC20 private tokenB;
    MockWrappedNative private wrappedNative;
    MockPermit2 private permit2;
    MockUniswapV4PoolManager private manager;
    UniswapV4Executor private executor;
    SwapRouter private router;

    function setUp() public {
        tokenA = new MockERC20("Token A", "A");
        tokenB = new MockERC20("Token B", "B");
        wrappedNative = new MockWrappedNative();
        permit2 = new MockPermit2();
        manager = new MockUniswapV4PoolManager();
        executor = new UniswapV4Executor(address(manager), address(wrappedNative));

        address[] memory executors = new address[](1);
        executors[0] = address(executor);
        router = new SwapRouter(address(this), address(wrappedNative), address(permit2), executors);

        tokenA.mint(USER, 10_000);
        tokenB.mint(address(manager), 100_000);
        tokenA.mint(address(manager), 100_000);
        vm.deal(address(manager), 100_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
        vm.prank(USER);
        tokenB.approve(address(permit2), type(uint256).max);
    }

    function testExactInputERC20Pool() public {
        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            _exactInputParams(address(tokenA), address(tokenB), 100, 200, _key(address(tokenA), address(tokenB))),
            _permit(0)
        );

        assertEq(amountOut, 200);
        assertEq(tokenB.balanceOf(RECIPIENT), 200);
    }

    function testExactOutputERC20Pool() public {
        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2(
            _exactOutputParams(address(tokenA), address(tokenB), 100, 60, _key(address(tokenA), address(tokenB))),
            _permit(0)
        );

        assertEq(amountIn, 50);
        assertEq(tokenA.balanceOf(USER), 9950);
        assertEq(tokenB.balanceOf(RECIPIENT), 100);
    }

    function testExactInputNativeCurrencyPool() public {
        vm.deal(USER, 100);
        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2{ value: 100 }(
            _exactInputParams(address(0), address(tokenB), 100, 200, _key(address(0), address(tokenB))),
            ISwapRouter.Permit2Permit({ nonce: 0, signature: bytes("") })
        );

        assertEq(amountOut, 200);
        assertEq(tokenB.balanceOf(RECIPIENT), 200);
    }

    function testExactInputToNativeCurrency() public {
        uint256 recipientBefore = RECIPIENT.balance;
        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            _exactInputParams(address(tokenA), address(0), 100, 200, _key(address(0), address(tokenA))), _permit(0)
        );

        assertEq(amountOut, 200);
        assertEq(RECIPIENT.balance - recipientBefore, 200);
    }

    function testRejectsPoolsWithHooks() public {
        PoolKey memory key = _key(address(tokenA), address(tokenB));
        key.hooks = address(0xBEEF);

        vm.expectRevert(abi.encodeWithSelector(UniswapV4Executor.InvalidHooks.selector, key.hooks));
        vm.prank(USER);
        router.exactInputWithPermit2(_exactInputParams(address(tokenA), address(tokenB), 100, 1, key), _permit(0));
    }

    function testRejectsUnexpectedUnlockCallback() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapV4Executor.InvalidSwapCallback.selector, address(this)));
        executor.unlockCallback(bytes(""));
    }

    function testRouterRejectsPoolManagerNativeTransferOutsideExecution() public {
        bytes memory errorData =
            abi.encodeWithSelector(ISwapRouter.UnexpectedCallback.selector, bytes4(0), address(manager));
        vm.expectRevert(errorData);
        manager.sendNative(address(router), 1);
    }

    function _exactInputParams(
        address rawTokenIn,
        address rawTokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        PoolKey memory key
    )
        private
        view
        returns (RouteTypes.ExactInputParams memory params)
    {
        address tokenOut = rawTokenOut == address(0) ? address(wrappedNative) : rawTokenOut;
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        bytes memory poolData = abi.encode(key);
        steps[0] = RouteTypes.ExactInputStep({ executor: address(executor), tokenOut: tokenOut, data: poolData });
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
        params = RouteTypes.ExactInputParams({
            tokenIn: rawTokenIn,
            tokenOut: rawTokenOut,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            recipient: RECIPIENT,
            deadline: block.timestamp,
            paths: paths
        });
    }

    function _exactOutputParams(
        address rawTokenIn,
        address rawTokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        PoolKey memory key
    )
        private
        view
        returns (RouteTypes.ExactOutputParams memory params)
    {
        address tokenOut = rawTokenOut == address(0) ? address(wrappedNative) : rawTokenOut;
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](1);
        steps[0] = RouteTypes.ExactOutputStep({
            executor: address(executor),
            tokenOut: tokenOut,
            amountOut: amountOut,
            data: abi.encode(key)
        });
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });
        params = RouteTypes.ExactOutputParams({
            tokenIn: rawTokenIn,
            tokenOut: rawTokenOut,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            recipient: RECIPIENT,
            deadline: block.timestamp,
            paths: paths
        });
    }

    function _key(address currencyA, address currencyB) private pure returns (PoolKey memory key) {
        address currency0 = currencyA;
        address currency1 = currencyB;
        if (currency0 > currency1) (currency0, currency1) = (currency1, currency0);
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });
    }

    function _permit(uint48 nonce) private pure returns (ISwapRouter.Permit2Permit memory) {
        return ISwapRouter.Permit2Permit({ nonce: nonce, signature: hex"01" });
    }
}
