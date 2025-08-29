//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Stablecoin Engine (DSCEngine)
 * @author Leticia Azevedo
 * @notice Users can deposit collateral and mint LCD (LetiCarolinaDollar).
 * @dev Maintains over-collateralization, liquidation if HF < 1.
 */

///what do I want my contract to do?
//deposit their collateral, redeem LCD from the collateral
//burn LCD to have more collateral, our DSC system should be overcollateralized
//at no point should the value of the all collateral be =< backed value of LCD
//AKA we should always have more collateral
//liquidate function users can call in case their collateral goes way too down
/**
 * @notice Deposit collateral and mint LCD against it.
 * @dev Reverts if resulting health factor < 1. System should be overcollateralized
 * @dev liquidate function users can call in case their collateral goes way too down
 */
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////////////////
    ///////////////----CUSTOM ERRORS------//////////
    ////////////////////////////////////////////////
    error DSCEngine__AmountShouldBeMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLenght();
    error DSCEngine__NotAllowedTokenAddress();
    error DSCEngine__TransferFailed();

    ////////////////////////////////////////////////
    ///////////////---STATE VARIABLES------/////////
    ////////////////////////////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; //TokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    DecentralizedStableCoin private immutable i_lcd;

    ////////////////////////////////////////////////
    ///////////////---EVENTS------//////////////////
    ////////////////////////////////////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    ////////////////////////////////////////////////
    ///////////////----MODIFIERS------//////////////
    ////////////////////////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountShouldBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedTokenAddress();
        }
        _;
    }

    ////////////////////////////////////////////////
    ///////////////----FUNCTIONS------//////////////
    ////////////////////////////////////////////////
    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address lcdAdress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLenght();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i] = priceFeedAddress[i]];
        }
        i_lcd = DecentralizedStableCoin(lcdAdress);
    }

    ////////////////////////////////////////////////
    ///////////////--EXTERNAL FUNCTIONS---//////////
    ////////////////////////////////////////////////
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice This is how users acquire the stablecoin, they deposit collateral greater than the value of the DSC minted
     * @notice follows CEI Pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     *
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //effect
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        //interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    //Users will need to be able to return DSC to the protocol in exchange for their underlying collateral
    function redeemCollateral() external {}

    function mintDsc() external {}

    //If the value of a user's collateral quickly falls,
    //users will need a way to quickly rectify the collateralization of their LCD.
    function burnDsc() external {}

    function liquidate() external {}

    //View an account's healthFactor
    //healthFactor will be defined as a certain ratio of collateralization a user has for the DSC they've minted.
    //As the value of a user's collateral falls, as will their healthFactor, if no changes to DSC held are made.
    //If a user's healthFactor falls below a defined threshold, the user will be at risk of liquidation.
    function getHealthFactor() external view {}
}

//threshold lets say 150%
//user pays 100 Dollar worth of ETH
//We give them back 50$ of LCD
//then ETH value goes down to 74$ that's under the 150% threshold
//so they go undercollaterized, meaning they get liquidated and
//other users can pay their "debt" and get their collateral for a discount to remove their previous position and save the protocol
//Because our protocol must always be over-collateralized (more collateral must be deposited then LCD is minted),
//if a user's collateral value falls below what's required to support their minted DSC, they can be liquidated.
//Liquidation allows other users to close an under-collateralized position
