// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAdresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wETHPriceFeedAddress,
            address wBTCPriceFeedAddress,
            address wETH,
            address wBTC,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        priceFeedAdresses = [wETHPriceFeedAddress, wBTCPriceFeedAddress];
        tokenAddresses = [wETH, wBTC];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin lcd = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAdresses,
            address(lcd)
        );
        lcd.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
    }
}
