// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETHPriceFeedAddress;
        address wBTCPriceFeedAddress;
        address wETH;
        address wBTC;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 1115511) {
            activeNetworkConfig = getETHSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilETHConfig();
        }
    }

    function getETHSepoliaConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wETHPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wBTCPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                wETH: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                wBTC: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
                deployerKey: vm.envUint("SEPOLIA_PK")
            });
    }

    function getOrCreateAnvilETHConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wETHPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );

        ERC20Mock wethMock = new ERC20Mock();
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return
            NetworkConfig({
                wETHPriceFeedAddress: address(ethUsdPriceFeed),
                wBTCPriceFeedAddress: address(btcUsdPriceFeed),
                wETH: address(wethMock),
                wBTC: address(wbtcMock),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
