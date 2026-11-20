// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { DeploySwapRouter } from "../../script/DeploySwapRouter.s.sol";
import { DeployCreate3Factory } from "../../script/DeployCreate3Factory.s.sol";
import { SwapRouter } from "../../src/SwapRouter.sol";
import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";
import { MockExecutor } from "../mocks/MockExecutor.sol";
import { MockPermit2 } from "../mocks/MockPermit2.sol";
import { MockWrappedNative } from "../mocks/MockWrappedNative.sol";

contract DeploySwapRouterTest is Test {
    uint256 private constant DEPLOYER_KEY = 1;
    bytes32 private constant ROUTER_SALT = keccak256("swap-router-v1");

    address private deployer;
    address private expected;
    MockExecutor private executor;
    MockPermit2 private permit2;
    MockWrappedNative private wrappedNative;
    DeploySwapRouter private script;

    function setUp() public {
        deployer = vm.addr(DEPLOYER_KEY);
        executor = new MockExecutor();
        permit2 = new MockPermit2();
        wrappedNative = new MockWrappedNative();
        script = new DeploySwapRouter();

        vm.setEnv("CHAIN_ID", vm.toString(block.chainid));
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));
        vm.setEnv("ROUTER_SALT", vm.toString(ROUTER_SALT));
        vm.setEnv("ROUTER_OWNER", vm.toString(address(this)));
        vm.setEnv("WRAPPED_NATIVE", vm.toString(address(wrappedNative)));
        vm.setEnv("PERMIT_2", vm.toString(address(permit2)));
        vm.setEnv("EXECUTOR_ADDRESSES", vm.toString(address(executor)));
        vm.startBroadcast(DEPLOYER_KEY);
        vm.stopBroadcast();
    }

    /// @dev Environment cheatcodes mutate process state, so all cases run sequentially in one test.
    function testDeploymentPreflightAndResult() public {
        vm.setEnv("CHAIN_ID", vm.toString(block.chainid + 1));
        vm.expectRevert(
            abi.encodeWithSelector(DeploySwapRouter.UnexpectedChain.selector, block.chainid + 1, block.chainid)
        );
        script.run();
        vm.setEnv("CHAIN_ID", vm.toString(block.chainid));

        DeployCreate3Factory factoryScript = new DeployCreate3Factory();
        vm.expectRevert(
            abi.encodeWithSelector(DeploySwapRouter.MissingFactory.selector, vm.computeCreateAddress(deployer, 0))
        );
        script.run();

        uint256 usedKey = DEPLOYER_KEY + 1;
        address usedDeployer = vm.addr(usedKey);
        vm.setNonce(usedDeployer, 1);
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(usedKey));
        vm.expectRevert(
            abi.encodeWithSelector(DeployCreate3Factory.UnexpectedDeployerNonce.selector, usedDeployer, uint64(1))
        );
        factoryScript.run();
        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));

        CREATE3Factory factory = factoryScript.run();
        assertEq(address(factory), vm.computeCreateAddress(deployer, 0));
        assertEq(address(factoryScript.run()), address(factory));
        expected = factory.getDeployed(deployer, ROUTER_SALT);

        SwapRouter router = script.run();
        assertEq(address(router), expected);
        assertEq(router.owner(), address(this));
        assertEq(router.wrappedNative(), address(wrappedNative));
        assertEq(router.permit2(), address(permit2));
        assertTrue(router.isExecutor(address(executor)));

        vm.expectRevert(abi.encodeWithSelector(DeploySwapRouter.RouterAlreadyDeployed.selector, expected));
        script.run();
    }
}
