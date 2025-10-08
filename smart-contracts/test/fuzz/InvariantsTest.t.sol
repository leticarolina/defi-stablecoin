// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol"; //so test contract can use Foundry’s invariant testing helpers — e.g. targetContract(), targetSelector(), fuzzing state, etc.
import {DeployAZD} from "../../script/DeployAZD.s.sol";
import {AZDEngine} from "../../src/AZDEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployAZD deployer;
    AZDEngine AZDe;
    DecentralizedStableCoin AZD;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;
    address public USER = makeAddr("user");

    function setUp() external {
        deployer = new DeployAZD();
        (AZD, AZDe, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        handler = new Handler(AZDe, AZD);
        targetContract(address(handler)); // fuzz will call handler's public funcs
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = AZD.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(AZDe));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(AZDe));

        uint256 wethValue = AZDe.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = AZDe.getUSDValue(wbtc, totalWbtcDeposited);
        console.log("weth value:", wethValue);
        console.log("wbtc value:", wbtcValue);
        console.log("total supply:", totalSupply);
        console.log("times mint is called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    //layup invariant
    //What is the primary benefit of including invariant tests that specifically check if 'getter' functions consistently execute without failure during fuzzing?
    //A failure in a basic getter function often signals an underlying invalid or unexpected system state reached during the fuzzing process.
    function invariant_gettersShouldNotRevert() public view {
        // token to use for token-based getters (if any tokens configured)
        address[] memory cols = AZDe.getCollateralTokens();
        address token = cols.length > 0 ? cols[0] : address(0); //does cols.length has any address? if yes use the first one, else use address(0) which is an invalid address

        //no param getters
        AZDe.getLiquidationThreshold();
        AZDe.getPrecision();
        AZDe.getMinHealthFactor();

        // User-based getters
        AZDe.getHealthFactor(USER);
        AZDe.getAccountCollateralValue(USER);
        AZDe.getAccountInformation(USER);
        AZDe.getAZDMinted(USER);

        // Token list getter
        AZDe.getCollateralTokens();

        // Only call token-based getters if actually have a token configured
        if (token != address(0)) {
            AZDe.getUSDValue(token, 1e18);
            AZDe.getTokenAmountFromAZD(token, 1e18);
            AZDe.getPriceFeed(token);
            AZDe.getCollateralDeposited(USER, token);
        }
    }
}

//what are the invariants? properties of the system that should always hold true?
//The system should never become undercollateralized
//Only the AZDEngine contract should be able to mint or burn AZD.
//A user’s health factor must never drop below MINIMUM_HEALTH_FACTOR unless they are liquidatable.
//getter view can never revert
//What is a likely benefit of configuring a stateful fuzz testing tool to immediately fail a test run if *any* transaction reverts?
//It helps validate that test sequences, especially guided ones (e.g., using Handlers), are constructed correctly and only perform valid operations.
