// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { Script } from "forge-std/src/Script.sol";

import { CREATE3Factory } from "create3-factory/src/CREATE3Factory.sol";

/// @title DeployCreate3Factory
/// @notice Deploys the same factory address on every chain from the same fresh account at nonce zero.
contract DeployCreate3Factory is Script {
    error UnexpectedChain(uint256 expected, uint256 actual);
    error UnexpectedDeployerNonce(address deployer, uint64 nonce);
    error FactoryAddressChanged(address expected, address actual);
    error UnexpectedFactoryCode(address factory);

    /// @notice Deploys the factory and checks its configured address.
    /// @return factory Newly deployed CREATE3 factory.
    function run() external returns (CREATE3Factory factory) {
        uint256 chainId = vm.envUint("CHAIN_ID");
        if (block.chainid != chainId) revert UnexpectedChain(chainId, block.chainid);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address predicted = vm.computeCreateAddress(deployer, 0);
        bytes32 expectedCodeHash = keccak256(type(CREATE3Factory).runtimeCode);
        if (predicted.code.length != 0) {
            if (predicted.codehash != expectedCodeHash) revert UnexpectedFactoryCode(predicted);
            return CREATE3Factory(predicted);
        }
        uint64 nonce = vm.getNonce(deployer);
        if (nonce != 0) revert UnexpectedDeployerNonce(deployer, nonce);

        vm.startBroadcast(deployerKey);
        factory = new CREATE3Factory();
        vm.stopBroadcast();
        if (address(factory) != predicted) revert FactoryAddressChanged(predicted, address(factory));
        if (predicted.codehash != expectedCodeHash) revert UnexpectedFactoryCode(predicted);
    }
}
