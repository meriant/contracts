// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { RouterFixture } from "../fixtures/RouterFixture.sol";

contract ReentrantRecipient {
    address private immutable ROUTER;
    bytes private nestedCall;
    bool public blocked;

    error NestedSwapSucceeded();

    constructor(address router_) {
        ROUTER = router_;
    }

    function setNestedCall(bytes calldata callData) external {
        nestedCall = callData;
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = ROUTER.call{ value: 1 }(nestedCall);
        blocked = !success;
        if (!blocked) revert NestedSwapSucceeded();
    }
}

contract NativeConversionTest is RouterFixture {
    function testExactInputWrapsNative() public {
        uint256 userBefore = USER.balance;

        vm.prank(USER);
        uint256 amountOut = router.exactInput{ value: 100 }(
            _inputParams(address(0), address(wrappedNative), 100, 100, _inputPaths(100, address(wrappedNative)))
        );

        assertEq(amountOut, 100);
        assertEq(USER.balance, userBefore - 100);
        assertEq(wrappedNative.balanceOf(RECIPIENT), 100);
        assertEq(wrappedNative.balanceOf(address(router)), 0);
    }

    function testExactInputUnwrapsWithPermit2() public {
        wrappedNative.mint(USER, 100);
        vm.prank(USER);
        wrappedNative.approve(address(permit2), 100);
        uint256 recipientBefore = RECIPIENT.balance;

        vm.prank(USER);
        uint256 amountOut = router.exactInputWithPermit2(
            _inputParams(address(wrappedNative), address(0), 100, 100, _inputPaths(100, address(0))), _permit()
        );

        assertEq(amountOut, 100);
        assertEq(RECIPIENT.balance - recipientBefore, 100);
        assertEq(wrappedNative.balanceOf(address(router)), 0);
    }

    function testExactOutputWrapsAndRefundsNative() public {
        uint256 userBefore = USER.balance;

        vm.prank(USER);
        uint256 amountIn = router.exactOutput{ value: 120 }(
            _outputParams(address(0), address(wrappedNative), 100, 120, _outputPaths(address(wrappedNative)))
        );

        assertEq(amountIn, 100);
        assertEq(USER.balance, userBefore - 100);
        assertEq(wrappedNative.balanceOf(RECIPIENT), 100);
        assertEq(wrappedNative.balanceOf(address(router)), 0);
    }

    function testExactOutputUnwrapsAndRefundsWrappedNative() public {
        wrappedNative.mint(USER, 120);
        vm.prank(USER);
        wrappedNative.approve(address(router), 120);
        uint256 recipientBefore = RECIPIENT.balance;

        vm.prank(USER);
        uint256 amountIn =
            router.exactOutput(_outputParams(address(wrappedNative), address(0), 100, 120, _outputPaths(address(0))));

        assertEq(amountIn, 100);
        assertEq(wrappedNative.balanceOf(USER), 20);
        assertEq(RECIPIENT.balance - recipientBefore, 100);
        assertEq(wrappedNative.balanceOf(address(router)), 0);
    }

    function testRejectsNonConversionPair() public {
        vm.prank(USER);
        tokenA.approve(address(router), 100);
        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.InvalidExecutor.selector, address(0)));
        vm.prank(USER);
        router.exactInput(
            _inputParams(address(tokenA), address(wrappedNative), 100, 100, _inputPaths(100, address(wrappedNative)))
        );
    }

    function testRejectsUnexpectedExecutionData() public {
        RouteTypes.ExactInputPath[] memory paths = _inputPaths(100, address(wrappedNative));
        paths[0].steps[0].data = hex"01";

        vm.expectRevert(ISwapRouter.InvalidRoute.selector);
        vm.prank(USER);
        router.exactInput{ value: 100 }(_inputParams(address(0), address(wrappedNative), 100, 100, paths));
    }

    function testRejectsMultihopNativeConversion() public {
        RouteTypes.ExactInputPath[] memory paths = _inputPaths(100, address(wrappedNative));
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](2);
        steps[0] = paths[0].steps[0];
        steps[1] = paths[0].steps[0];
        paths[0].steps = steps;

        vm.expectRevert(ISwapRouter.InvalidRoute.selector);
        vm.prank(USER);
        router.exactInput{ value: 100 }(_inputParams(address(0), address(wrappedNative), 100, 100, paths));
    }

    function testRejectsExactOutputAboveInputLimit() public {
        vm.expectRevert(abi.encodeWithSelector(ISwapRouter.InputLimitExceeded.selector, 90, 100));
        vm.prank(USER);
        router.exactOutput{ value: 90 }(
            _outputParams(address(0), address(wrappedNative), 100, 90, _outputPaths(address(wrappedNative)))
        );
    }

    function testNativeOutputCannotReenterSwap() public {
        ReentrantRecipient recipient = new ReentrantRecipient(address(router));
        RouteTypes.ExactInputParams memory nested =
            _inputParams(address(0), address(wrappedNative), 1, 1, _inputPaths(1, address(wrappedNative)));
        nested.recipient = address(recipient);
        recipient.setNestedCall(abi.encodeCall(router.exactInput, (nested)));

        wrappedNative.mint(USER, 100);
        vm.prank(USER);
        wrappedNative.approve(address(router), 100);
        RouteTypes.ExactInputParams memory outer =
            _inputParams(address(wrappedNative), address(0), 100, 100, _inputPaths(100, address(0)));
        outer.recipient = address(recipient);

        vm.prank(USER);
        router.exactInput(outer);

        assertTrue(recipient.blocked());
        assertEq(address(recipient).balance, 100);
    }

    function _inputPaths(
        uint256 amount,
        address tokenOut
    )
        private
        view
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        paths = new RouteTypes.ExactInputPath[](1);
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({ executor: address(0), tokenOut: tokenOut, data: "" });
        paths[0] = RouteTypes.ExactInputPath({ amountIn: amount, steps: steps });
    }

    function _outputPaths(address tokenOut) private view returns (RouteTypes.ExactOutputPath[] memory paths) {
        paths = new RouteTypes.ExactOutputPath[](1);
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](1);
        steps[0] = RouteTypes.ExactOutputStep({ executor: address(0), tokenOut: tokenOut, amountOut: 100, data: "" });
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });
    }
}
