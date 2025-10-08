// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {AZDEngine} from "../src/AZDEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployAZD is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAdresses;

    function run()
        external
        returns (
            DecentralizedStableCoin azd,
            AZDEngine azdEngine,
            HelperConfig helperConfig
        )
    {
        helperConfig = new HelperConfig();
        (
            address wETHPriceFeedAddress,
            address wBTCPriceFeedAddress,
            address wETH,
            address wBTC,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        priceFeedAdresses = [wETHPriceFeedAddress, wBTCPriceFeedAddress];
        tokenAddresses = [wETH, wBTC];

        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        azd = new DecentralizedStableCoin(deployer);
        azdEngine = new AZDEngine(
            tokenAddresses,
            priceFeedAdresses,
            address(azd)
        );
        azd.transferOwnership(address(azdEngine));
        vm.stopBroadcast();

        return (azd, azdEngine, helperConfig);
    }
}
