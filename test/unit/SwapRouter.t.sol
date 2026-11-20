// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { RouterFixture } from "../fixtures/RouterFixture.sol";
import { MockExecutor } from "../mocks/MockExecutor.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";

contract SwapRouterTest is RouterFixture {
    function testExactInputDirectRouteAndArbitraryRecipient() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 amountOut =
            router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit());

        assertEq(amountOut, 200);
        assertEq(tokenA.balanceOf(USER), 9900);
        assertEq(tokenC.balanceOf(RECIPIENT), 200);
        _assertRouterBalancesAreZero();
    }

    function testSwapDoesNotIncludeExistingRouterBalanceInOutput() public {
        tokenC.mint(address(router), 50);
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 amountOut =
            router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit());

        assertEq(amountOut, 200);
        assertEq(tokenC.balanceOf(RECIPIENT), 200);
        assertEq(tokenC.balanceOf(address(router)), 50);
    }

    function testExactInputUsesRouterApproval() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));
        vm.prank(USER);
        tokenA.approve(address(router), 100);

        vm.prank(USER);
        uint256 amountOut = router.exactInput(_inputParams(address(tokenA), address(tokenC), 100, 200, paths));

        assertEq(amountOut, 200);
        assertEq(tokenA.balanceOf(USER), 9900);
        assertEq(tokenC.balanceOf(RECIPIENT), 200);
        _assertRouterBalancesAreZero();
    }

    function testExactInputRequiresRouterApproval() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert();
        vm.prank(USER);
        router.exactInput(_inputParams(address(tokenA), address(tokenC), 100, 200, paths));
    }

    function testSignedPermit2AllowanceIsConsumedWithoutRouterTokenApproval() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        assertEq(tokenA.allowance(USER, address(router)), 0);

        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit());

        (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(USER, address(tokenA), address(router));
        assertEq(amount, 0);
        assertEq(expiration, DEADLINE);
        assertEq(nonce, 1);
        assertEq(tokenA.allowance(USER, address(router)), 0);
    }

    function testExistingPermit2AllowanceDoesNotRequireSignature() public {
        vm.prank(USER);
        permit2.approve(address(tokenA), address(router), 100, DEADLINE);
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            _inputParams(address(tokenA), address(tokenC), 100, 200, paths), _emptyPermit()
        );

        assertEq(amountOut, 200);
        assertEq(tokenC.balanceOf(RECIPIENT), 200);
    }

    function testERC20InputWithoutPermit2AllowanceReverts() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert(MockPermit2.AllowanceExpired.selector);
        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _emptyPermit());

        assertEq(tokenA.balanceOf(USER), 10_000);
    }

    function testExactInputMixedProtocolMultihopRoute() public {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](2);
        steps[0] = _inputStep(address(executorA), address(tokenB), 2, 1);
        steps[1] = _inputStep(address(executorB), address(tokenC), 3, 1);

        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 100, steps: steps });

        vm.prank(USER);
        uint256 amountOut =
            router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 600, paths), _permit());

        assertEq(amountOut, 600);
        assertEq(tokenC.balanceOf(RECIPIENT), 600);
        _assertRouterBalancesAreZero();
    }

    function testExecutorCanHandlePoolCallbackThroughRouter() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(callbackExecutor), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 amountOut =
            router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit());

        assertEq(amountOut, 200);
        assertEq(tokenA.balanceOf(address(callbackPool)), 100);
        assertEq(tokenC.balanceOf(RECIPIENT), 200);
        _assertRouterBalancesAreZero();
        _assertUnexpectedCallbackRejected();
    }

    function testExactOutputDirectRouteRefundsUnusedInput() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 100, 2, 1));

        vm.prank(USER);
        uint256 amountIn =
            router.exactOutputWithPermit2(_outputParams(address(tokenA), address(tokenC), 100, 60, paths), _permit());

        assertEq(amountIn, 50);
        assertEq(tokenA.balanceOf(USER), 9950);
        assertEq(tokenC.balanceOf(RECIPIENT), 100);
        _assertRouterBalancesAreZero();
    }

    function testExactOutputRefundsUnusedInputWithRouterApproval() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 100, 2, 1));
        vm.prank(USER);
        tokenA.approve(address(router), 60);

        vm.prank(USER);
        uint256 amountIn = router.exactOutput(_outputParams(address(tokenA), address(tokenC), 100, 60, paths));

        assertEq(amountIn, 50);
        assertEq(tokenA.balanceOf(USER), 9950);
        assertEq(tokenC.balanceOf(RECIPIENT), 100);
        _assertRouterBalancesAreZero();
    }

    function testExactOutputMixedProtocolMultihopRoute() public {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](2);
        steps[0] = _outputStep(address(executorA), address(tokenB), 30, 2, 1);
        steps[1] = _outputStep(address(executorB), address(tokenC), 90, 3, 1);

        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });
        RouteTypes.ExactOutputParams memory params = _outputParams(address(tokenA), address(tokenC), 90, 20, paths);

        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2(params, _permit());

        assertEq(amountIn, 15);
        assertEq(tokenA.balanceOf(USER), 9985);
        assertEq(tokenC.balanceOf(RECIPIENT), 90);
        _assertRouterBalancesAreZero();
    }

    function testExactOutputMultihopRefundsUnusedIntermediateToken() public {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](2);
        steps[0] = _outputStep(address(executorA), address(tokenB), 40, 2, 1);
        steps[1] = _outputStep(address(executorB), address(tokenC), 90, 3, 1);

        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });
        RouteTypes.ExactOutputParams memory params = _outputParams(address(tokenA), address(tokenC), 90, 25, paths);

        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2(params, _permit());

        assertEq(amountIn, 20);
        assertEq(tokenB.balanceOf(USER), 10);
        assertEq(tokenC.balanceOf(RECIPIENT), 90);
        _assertRouterBalancesAreZero();
    }

    function testSplitExactInputRoute() public {
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](2);
        paths[0] = _exactInputPath(40, _inputStep(address(executorA), address(tokenC), 2, 1));

        RouteTypes.ExactInputStep[] memory multihopSteps = new RouteTypes.ExactInputStep[](2);
        multihopSteps[0] = _inputStep(address(executorA), address(tokenB), 2, 1);
        multihopSteps[1] = _inputStep(address(executorB), address(tokenC), 3, 1);
        paths[1] = RouteTypes.ExactInputPath({ amountIn: 60, steps: multihopSteps });

        vm.prank(USER);
        uint256 amountOut =
            router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 440, paths), _permit());

        assertEq(amountOut, 440);
        assertEq(tokenC.balanceOf(RECIPIENT), 440);
        _assertRouterBalancesAreZero();
    }

    function testSplitExactOutputRoute() public {
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](2);
        paths[0] = _exactOutputPath(_outputStep(address(executorA), address(tokenC), 40, 2, 1));

        RouteTypes.ExactOutputStep[] memory multihopSteps = new RouteTypes.ExactOutputStep[](2);
        multihopSteps[0] = _outputStep(address(executorA), address(tokenB), 20, 2, 1);
        multihopSteps[1] = _outputStep(address(executorB), address(tokenC), 60, 3, 1);
        paths[1] = RouteTypes.ExactOutputPath({ steps: multihopSteps });

        vm.prank(USER);
        uint256 amountIn =
            router.exactOutputWithPermit2(_outputParams(address(tokenA), address(tokenC), 100, 40, paths), _permit());

        assertEq(amountIn, 30);
        assertEq(tokenA.balanceOf(USER), 9970);
        assertEq(tokenC.balanceOf(RECIPIENT), 100);
        _assertRouterBalancesAreZero();
    }

    function testExactInputRejectsIncorrectPathAllocation() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(99, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.IncorrectInputAmount.selector, 100, 99));
        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 198, paths), _permit());

        assertEq(tokenA.balanceOf(USER), 10_000);
    }

    function testExactOutputRejectsIncorrectPathAllocation() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 99, 2, 1));

        vm.expectRevert(ISwapRouter.InvalidRoute.selector);
        vm.prank(USER);
        router.exactOutputWithPermit2(_outputParams(address(tokenA), address(tokenC), 100, 60, paths), _permit());

        assertEq(tokenA.balanceOf(USER), 10_000);
    }

    function testNativeInputIsWrappedBeforeExecution() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2{ value: 100 }(
            _inputParams(address(0), address(tokenC), 100, 200, paths), _emptyPermit()
        );

        assertEq(amountOut, 200);
        assertEq(tokenC.balanceOf(RECIPIENT), 200);
        _assertRouterBalancesAreZero();
    }

    function testNativeInputRequiresExactMessageValue() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.IncorrectNativeAmount.selector, 100, 99));
        vm.prank(USER);
        router.exactInputWithPermit2{ value: 99 }(
            _inputParams(address(0), address(tokenC), 100, 200, paths), _emptyPermit()
        );
    }

    function testERC20InputRejectsMessageValue() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.IncorrectNativeAmount.selector, 0, 1));
        vm.prank(USER);
        router.exactInputWithPermit2{ value: 1 }(
            _inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit()
        );
    }

    function testNativeOutputIsUnwrappedForRecipient() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(wrappedNative), 2, 1));
        uint256 recipientBalanceBefore = RECIPIENT.balance;

        vm.prank(USER);
        uint256 amountOut =
            router.exactInputWithPermit2(_inputParams(address(tokenA), address(0), 100, 200, paths), _permit());

        assertEq(amountOut, 200);
        assertEq(RECIPIENT.balance - recipientBalanceBefore, 200);
        _assertRouterBalancesAreZero();
    }

    function testExactOutputNativeInputRefundsUnusedNativeCurrency() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 100, 2, 1));
        uint256 userBalanceBefore = USER.balance;

        vm.prank(USER);
        uint256 amountIn = router.exactOutputWithPermit2{ value: 60 }(
            _outputParams(address(0), address(tokenC), 100, 60, paths), _emptyPermit()
        );

        assertEq(amountIn, 50);
        assertEq(userBalanceBefore - USER.balance, 50);
        assertEq(tokenC.balanceOf(RECIPIENT), 100);
        _assertRouterBalancesAreZero();
    }

    function testExactOutputNativeOutputIsUnwrappedForRecipient() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(wrappedNative), 100, 2, 1));
        uint256 recipientBalanceBefore = RECIPIENT.balance;

        vm.prank(USER);
        uint256 amountIn =
            router.exactOutputWithPermit2(_outputParams(address(tokenA), address(0), 100, 60, paths), _permit());

        assertEq(amountIn, 50);
        assertEq(RECIPIENT.balance - recipientBalanceBefore, 100);
        _assertRouterBalancesAreZero();
    }

    function testExpiredDeadlineReverts() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));
        RouteTypes.ExactInputParams memory params = _inputParams(address(tokenA), address(tokenC), 100, 200, paths);
        params.deadline = block.timestamp - 1;

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.DeadlineExpired.selector, params.deadline));
        vm.prank(USER);
        router.exactInputWithPermit2(params, _permit());
    }

    function testExactInputGlobalSlippageRevertsEntireRoute() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.SlippageExceeded.selector, 201, 200));
        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 201, paths), _permit());

        assertEq(tokenA.balanceOf(USER), 10_000);
        assertEq(tokenC.balanceOf(RECIPIENT), 0);
    }

    function testExactOutputGlobalInputLimitRevertsEntireRoute() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 100, 2, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.InputLimitExceeded.selector, 49, 50));
        vm.prank(USER);
        router.exactOutputWithPermit2(_outputParams(address(tokenA), address(tokenC), 100, 49, paths), _permit());

        assertEq(tokenA.balanceOf(USER), 10_000);
        assertEq(tokenC.balanceOf(RECIPIENT), 0);
    }

    function testDisabledExecutorRevertsAtomically() public {
        router.setExecutor(address(executorA), false);
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.InvalidExecutor.selector, address(executorA)));
        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit());

        assertEq(tokenA.balanceOf(USER), 10_000);
    }

    function testOnlyOwnerCanUpdateExecutor() public {
        MockExecutor executor = new MockExecutor();

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", USER));
        vm.prank(USER);
        router.setExecutor(address(executor), true);
    }

    function testOwnerCanRegisterAndUnregisterExecutor() public {
        MockExecutor executor = new MockExecutor();

        assertFalse(router.isExecutor(address(executor)));
        router.setExecutor(address(executor), true);
        assertTrue(router.isExecutor(address(executor)));

        router.setExecutor(address(executor), false);
        assertFalse(router.isExecutor(address(executor)));
    }

    function testOwnerCanRegisterAndUnregisterExecutorsAtomically() public {
        MockExecutor first = new MockExecutor();
        MockExecutor second = new MockExecutor();
        address[] memory executors = new address[](2);
        executors[0] = address(first);
        executors[1] = address(second);

        router.setExecutors(executors, true);
        assertTrue(router.isExecutor(address(first)));
        assertTrue(router.isExecutor(address(second)));

        router.setExecutors(executors, false);
        assertFalse(router.isExecutor(address(first)));
        assertFalse(router.isExecutor(address(second)));
    }

    function testOnlyOwnerCanUpdateExecutors() public {
        address[] memory executors = new address[](1);
        executors[0] = address(new MockExecutor());

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", USER));
        vm.prank(USER);
        router.setExecutors(executors, true);
    }

    function testCanRegisterAddressBeforeDeployment() public {
        address executor = address(0x1234);

        router.setExecutor(executor, true);
        assertTrue(router.isExecutor(executor));
    }

    function testConstructorRejectsInvalidWrappedNative() public {
        address[] memory executors = new address[](0);

        vm.expectRevert(ISwapRouter.InvalidAddress.selector);
        new SwapRouter(address(this), address(0), address(permit2), executors);
    }

    function testConstructorRejectsInvalidPermit2() public {
        address[] memory executors = new address[](0);

        vm.expectRevert(ISwapRouter.InvalidAddress.selector);
        new SwapRouter(address(this), address(wrappedNative), address(0), executors);
    }

    function testERC20InputRejectsAmountAbovePermit2Limit() public {
        uint256 amountIn = uint256(type(uint160).max) + 1;
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(amountIn, _inputStep(address(executorA), address(tokenC), 1, 1));

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.Permit2AmountOverflow.selector, amountIn));
        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), amountIn, 1, paths), _permit());
    }

    function testERC20InputRejectsDeadlineAbovePermit2Limit() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));
        RouteTypes.ExactInputParams memory params = _inputParams(address(tokenA), address(tokenC), 100, 200, paths);
        params.deadline = uint256(type(uint48).max) + 1;

        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.Permit2DeadlineOverflow.selector, params.deadline));
        vm.prank(USER);
        router.exactInputWithPermit2(params, _permit());
    }

    function testExactInputRejectsPathEndingInWrongToken() public {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](2);
        steps[0] = _inputStep(address(executorA), address(tokenB), 2, 1);
        steps[1] = _inputStep(address(executorB), address(tokenA), 3, 1);

        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 100, steps: steps });

        vm.expectRevert(ISwapRouter.InvalidRoute.selector);
        vm.prank(USER);
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 600, paths), _permit());
    }

    function testExactOutputRejectsPathEndingInWrongToken() public {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](2);
        steps[0] = _outputStep(address(executorA), address(tokenB), 30, 2, 1);
        steps[1] = _outputStep(address(executorB), address(tokenA), 90, 3, 1);

        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });

        vm.expectRevert(ISwapRouter.InvalidRoute.selector);
        vm.prank(USER);
        router.exactOutputWithPermit2(_outputParams(address(tokenA), address(tokenC), 90, 20, paths), _permit());

        assertEq(tokenA.balanceOf(USER), 10_000);
    }

    function testUnexpectedCallbackIsRejected() public {
        _assertUnexpectedCallbackRejected();
    }

    function testFuzzExactInputPreservesAmountAccounting(uint96 rawAmountIn, uint8 rawMultiplier) public {
        uint256 amountIn = bound(uint256(rawAmountIn), 1, type(uint96).max);
        uint256 multiplier = bound(uint256(rawMultiplier), 1, 10);
        uint256 expectedAmountOut = amountIn * multiplier;
        tokenA.mint(USER, amountIn);
        uint256 userBalanceBefore = tokenA.balanceOf(USER);

        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(amountIn, _inputStep(address(executorA), address(tokenC), multiplier, 1));

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            _inputParams(address(tokenA), address(tokenC), amountIn, expectedAmountOut, paths), _permit()
        );

        assertEq(userBalanceBefore - tokenA.balanceOf(USER), amountIn);
        assertEq(amountOut, expectedAmountOut);
        assertEq(tokenC.balanceOf(RECIPIENT), expectedAmountOut);
        _assertRouterBalancesAreZero();
    }

    function testFuzzExactOutputRefundsTheUnusedMaximum(
        uint96 rawAmountOut,
        uint8 rawMultiplier,
        uint96 rawRefund
    )
        public
    {
        uint256 amountOut = bound(uint256(rawAmountOut), 1, type(uint96).max);
        uint256 multiplier = bound(uint256(rawMultiplier), 1, 10);
        uint256 amountIn = _ceilDiv(amountOut, multiplier);
        uint256 refund = bound(uint256(rawRefund), 0, type(uint96).max);
        uint256 amountInMaximum = amountIn + refund;
        tokenA.mint(USER, amountInMaximum);
        uint256 userBalanceBefore = tokenA.balanceOf(USER);

        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), amountOut, multiplier, 1));

        vm.prank(USER);
        uint256 actualAmountIn = router.exactOutputWithPermit2(
            _outputParams(address(tokenA), address(tokenC), amountOut, amountInMaximum, paths), _permit()
        );

        assertEq(actualAmountIn, amountIn);
        assertEq(userBalanceBefore - tokenA.balanceOf(USER), amountIn);
        assertEq(tokenC.balanceOf(RECIPIENT), amountOut);
        _assertRouterBalancesAreZero();
    }

    function _assertUnexpectedCallbackRejected() private {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = address(router).call(hex"01020304");

        assertFalse(success);
        assertEq(
            result, abi.encodeWithSelector(ISwapRouter.UnexpectedCallback.selector, bytes4(0x01020304), address(this))
        );
    }

    function _ceilDiv(uint256 value, uint256 denominator) private pure returns (uint256) {
        return value == 0 ? 0 : (value - 1) / denominator + 1;
    }
}
