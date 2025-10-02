// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A broken ERC20 mock that always fails transfers
contract ERC20FailMock is IERC20 {
    string public name = "Fail Token";
    string public symbol = "FAIL";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(uint256 _initialSupply) {
        _balances[msg.sender] = _initialSupply;
        totalSupply = _initialSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false; // always fail
    }

    function allowance(address, address) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return true; // pretend approve works
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return false; // always fail
    }
}
