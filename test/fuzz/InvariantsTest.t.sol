// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        targetContract(address(dsce));
    }

    // function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
    // uint256 totalSupply = dsc.totalSupply();
    // uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
    // uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

    // uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
    // uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
    // assert(wethValue + wbtcValue > totalSupply);
    // }
}

//what are the invariants? properties of the system that should always hold true?
//The system should never become undercollateralized
//Only the DSCEngine contract should be able to mint or burn DSC.
//A user’s health factor must never drop below MINIMUM_HEALTH_FACTOR unless they are liquidatable.
//getter view can never revert
