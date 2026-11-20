// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Script } from "forge-std/src/Script.sol";

import { SwapRouter } from "../src/SwapRouter.sol";
import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";

/// @title DeploySwapRouter
/// @notice Deploys a chain-specific router configuration to the same CREATE3 address on every chain.
contract DeploySwapRouter is Script {
    error UnexpectedChain(uint256 expected, uint256 actual);
    error MissingFactory(address factory);
    error RouterAlreadyDeployed(address router);
    error UnexpectedRouterAddress(address expected, address actual);
    error UnexpectedRouterConfiguration();
    error ExecutorNotRegistered(address executor);

    /// @notice Deploys and verifies the router using the configured factory, caller, and salt.
    /// @return router Router deployed by the factory.
    function run() external returns (SwapRouter router) {
        uint256 chainId = vm.envUint("CHAIN_ID");
        if (block.chainid != chainId) revert UnexpectedChain(chainId, block.chainid);

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        vm.stopBroadcast();
        CREATE3Factory factory = _factory(deployer);
        bytes32 salt = vm.envBytes32("ROUTER_SALT");
        address predicted = factory.getDeployed(deployer, salt);
        if (predicted.code.length != 0) revert RouterAlreadyDeployed(predicted);

        address wrappedNative = vm.envAddress("WRAPPED_NATIVE");
        address permit2 = vm.envAddress("PERMIT_2");
        address owner = vm.envAddress("ROUTER_OWNER");
        address[] memory executors = vm.envAddress("EXECUTOR_ADDRESSES", ",");
        bytes memory creationCode =
            abi.encodePacked(type(SwapRouter).creationCode, abi.encode(owner, wrappedNative, permit2, executors));

        vm.startBroadcast();
        address deployed = factory.deploy(salt, creationCode);
        vm.stopBroadcast();

        if (deployed != predicted) revert UnexpectedRouterAddress(predicted, deployed);
        router = SwapRouter(payable(deployed));
        if (router.owner() != owner || router.wrappedNative() != wrappedNative || router.permit2() != permit2) {
            revert UnexpectedRouterConfiguration();
        }
        for (uint256 index; index < executors.length; ++index) {
            if (!router.isExecutor(executors[index])) revert ExecutorNotRegistered(executors[index]);
        }
    }

    /// @dev Returns the expected factory after checking that it is deployed.
    function _factory(address deployer) private view returns (CREATE3Factory factory) {
        factory = CREATE3Factory(vm.computeCreateAddress(deployer, 0));
        if (address(factory).code.length == 0) revert MissingFactory(address(factory));
    }
}
