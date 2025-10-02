// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal DSC mock that always fails `mint`
contract DSCFailMock is IERC20 {
    string public name = "Fail Stablecoin";
    string public symbol = "fDSC";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return true; // allow transfers
    }

    function allowance(address, address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return true;
    }

    /// @dev same signature as your real DecentralizedStableCoin mint
    function mint(address, uint256) external pure returns (bool) {
        return false; // always fail
    }
}
