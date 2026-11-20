// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IWrappedNative } from "../../src/interfaces/IWrappedNative.sol";

contract MockWrappedNative is ERC20, IWrappedNative {
    error NativeTransferFailed();

    constructor() ERC20("Wrapped Native", "WNATIVE") { }

    receive() external payable {
        deposit();
    }

    function deposit() public payable override {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{ value: amount }("");
        if (!success) revert NativeTransferFailed();
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
