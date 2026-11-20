// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockExecutor } from "../mocks/MockExecutor.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

contract CalldataCompatibilityTest is Test {
    uint48 private constant DEADLINE = 2_000_000_000;

    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);
    address private constant TOKEN_A = 0x000000000000000000000000000000000000a001;
    address private constant TOKEN_B = 0x000000000000000000000000000000000000A002;
    address private constant TOKEN_C = 0x000000000000000000000000000000000000a003;
    address private constant EXECUTOR_A = 0x000000000000000000000000000000000000e001;
    address private constant EXECUTOR_B = 0x000000000000000000000000000000000000e002;

    bool private enabled;
    SwapRouter private router;
    MockERC20 private tokenA;
    MockERC20 private tokenC;
    MockPermit2 private permit2;

    function setUp() public {
        enabled = vm.envOr("ROUTER_GO_CALLDATA", false);
        if (!enabled) return;

        MockERC20 tokenImplementation = new MockERC20("Token", "T");
        MockExecutor executorImplementation = new MockExecutor();
        vm.etch(TOKEN_A, address(tokenImplementation).code);
        vm.etch(TOKEN_B, address(tokenImplementation).code);
        vm.etch(TOKEN_C, address(tokenImplementation).code);
        vm.etch(EXECUTOR_A, address(executorImplementation).code);
        vm.etch(EXECUTOR_B, address(executorImplementation).code);

        tokenA = MockERC20(TOKEN_A);
        tokenC = MockERC20(TOKEN_C);
        permit2 = new MockPermit2();
        MockWrappedNative wrappedNative = new MockWrappedNative();

        address[] memory executors = new address[](2);
        executors[0] = EXECUTOR_A;
        executors[1] = EXECUTOR_B;
        router = new SwapRouter(address(this), address(wrappedNative), address(permit2), executors);

        tokenA.mint(USER, 10_000);
        vm.prank(USER);
        tokenA.approve(address(permit2), type(uint256).max);
    }

    function testGoDirectExactInput() public {
        _execute("GO_DIRECT_EXACT_IN", 100, 200, 200, false);
    }

    function testGoDirectExactOutput() public {
        _execute("GO_DIRECT_EXACT_OUT", 50, 100, 50, false);
    }

    function testGoMixedProtocolMultihopExactInput() public {
        _execute("GO_MULTIHOP_EXACT_IN", 100, 600, 600, false);
    }

    function testGoMixedProtocolMultihopExactOutput() public {
        _execute("GO_MULTIHOP_EXACT_OUT", 15, 90, 15, false);
    }

    function testGoSplitExactInput() public {
        _execute("GO_SPLIT_EXACT_IN", 100, 440, 440, false);
    }

    function testGoSplitExactOutput() public {
        _execute("GO_SPLIT_EXACT_OUT", 30, 100, 30, false);
    }

    function testGoPermit2ExactInput() public {
        _execute("GO_PERMIT2_EXACT_IN", 100, 200, 200, true);
        (uint160 amount, uint48 expiration, uint48 nonce) = permit2.allowance(USER, TOKEN_A, address(router));
        assertEq(amount, 0);
        assertEq(expiration, DEADLINE);
        assertEq(nonce, 1);
    }

    function _execute(
        string memory variable,
        uint256 amountIn,
        uint256 amountOut,
        uint256 returnValue,
        bool signedPermit
    )
        private
    {
        if (!enabled) {
            vm.skip(true);
            return;
        }
        if (!signedPermit) {
            vm.prank(USER);
            tokenA.approve(address(router), amountIn);
        }

        bytes memory data = vm.envBytes(variable);
        vm.prank(USER);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = address(router).call(data);
        assertTrue(success, variable);
        assertEq(abi.decode(result, (uint256)), returnValue);
        assertEq(tokenA.balanceOf(USER), 10_000 - amountIn);
        assertEq(tokenC.balanceOf(RECIPIENT), amountOut);
        assertEq(tokenA.balanceOf(address(router)), 0);
        assertEq(tokenC.balanceOf(address(router)), 0);
    }
}
