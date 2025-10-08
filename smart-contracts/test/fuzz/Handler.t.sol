// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol"; //so test contract can use Foundry’s invariant testing helpers — e.g. targetContract(), targetSelector(), fuzzing state, etc.
import {DeployAZD} from "../../script/DeployAZD.s.sol";
import {AZDEngine} from "../../src/AZDEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../lib/chainlink-evm/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

//here will be the functions that the handler can call before each invariant test
contract Handler is StdInvariant, Test {
    AZDEngine AZDe; //so the handler knows what the AZD engine is
    DecentralizedStableCoin AZD;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; //get the max uint96 value
    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    address public USER = makeAddr("user");

    constructor(AZDEngine _AZDEngine, DecentralizedStableCoin _AZD) {
        AZDe = _AZDEngine;
        AZD = _AZD;

        address[] memory collateralTokens = AZDe.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(AZDe.getPriceFeed(address(weth)));
    }

    function mintAZD(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length]; //get a random user from the array, addressSeed is a random number provided by Foundry
        (uint256 totalAZDMinted, uint256 collateralValueInUsd) = AZDe.getAccountInformation(sender);
        int256 collateralAdjusted =
            (int256(collateralValueInUsd) * int256(AZDe.getLiquidationThreshold())) / int256(AZDe.getPrecision()); //Apply liquidation threshold (80%) i.e. (collateralValueInUsd * 80 / 1e18)
        int256 maxAZDToMint = (collateralAdjusted - int256(totalAZDMinted)); //divid
        if (maxAZDToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxAZDToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        AZDe.mintAZD(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    //parametra are randomnized
    //this has cut revert amount down to zer0
    //invariant_protocolMustHaveMoreValueThanTotalSupply() (runs: 200, calls: 40000, reverts: 0)
    /**
     * @notice Deposits collateral into the AZDEngine contract on behalf of the caller.
     * @dev Parameters are fuzzed to test various scenarios.
     * @param collateralSeed A seed to determine which collateral type to deposit (e.g., WETH or WBTC).
     * @param amountCollateral The amount of collateral to deposit, bounded to a maximum size.
     * This is similar to depositCollateral function in AZDEngine.sol but with fuzzed params and we want this to always succeed
     */
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE); //bound is from stdutils, bounds the result to an amount
        //bound() means amountCollateral will always be between 1 and MAX_DEPOSIT_SIZE

        vm.startPrank(USER);
        collateral.mint(USER, amountCollateral);
        collateral.approve(address(AZDe), amountCollateral);
        AZDe.depositCollateral(address(collateral), amountCollateral); //calls with valid address so it won't revert

        //double push
        usersWithCollateralDeposited.push(USER);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // getCollateralDeposited reads the user’s current balance using the *EOA* (msg.sender in Handler context)
        uint256 maxCollateralToRedeem = AZDe.getCollateralDeposited(msg.sender, address(collateral));
        //they should only be redeeming as much as they put in the system
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem); //force the input values within a specific valid range
        if (amountCollateral == 0) {
            return;
        }
        // Make the call as that same user
        vm.prank(msg.sender);
        AZDe.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    //breaks invariant test suite, if price of an asset plummets too quick the system breaks
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    //HELPERS
    //can only get a valid collateral type
    //this function will return either weth or wbtc based on the seed
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

//narrow down the way we call functions, so no wasted runs
//eg. only call redeemCollateral when there is actually collateral in there to redeem
