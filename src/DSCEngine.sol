//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Stablecoin Engine (DSCEngine)
 * @author Leticia Azevedo
 * @notice Users can deposit collateral and mint LCD (LetiCarolinaDollar).
 * @dev Maintains over-collateralization, liquidation if HF < 1.
 */

///what do I want my contract to do?
//deposit their collateral(eg.eth), then redeem LCD from the collateral (mint)
//burn LCD when returned to have more collateral, our DSC system should be overcollateralized
//at no point should the value of the all collateral be =< less than backed value of LCD
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
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

//v2.27.0

contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////////////////
    ///////////////----CUSTOM ERRORS------//////////
    ////////////////////////////////////////////////
    error DSCEngine__AmountShouldBeMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLength();
    error DSCEngine__NotAllowedTokenAddress();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthfactor);
    error DSCEngine__MintFailed();

    ////////////////////////////////////////////////
    ///////////////---STATE VARIABLES------/////////
    ////////////////////////////////////////////////
     DecentralizedStableCoin private immutable i_lcdAddress;
    mapping(address token => address priceFeed) private s_priceFeeds; //TokenToPriceFeed, maps each collateral token to its Chainlink price feed.
    mapping(address user => mapping(address token => uint256 amount)) //how much of each token a user deposited
        private s_collateralDeposited; //user address TO A mapping of token Address > amount minted from that token address
    mapping(address user => uint256 amountDSCMinted) s_DSCMinted; //How much each user has borrowed (minted)
    address[] private s_ArrayCollateralTokens;
    uint256 private constant ADDITIONAL_FEED_PRICE_PRECISION = 1e10; //because chainlink price feed is already 8 decimals
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;

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
            //If there’s no Pricefeed configured, that token isn’t allowed as collateral.
        }
        _;
    }

    ////////////////////////////////////////////////
    ///////////////----FUNCTIONS------//////////////
    ////////////////////////////////////////////////
    constructor(
        // inputs passed during deployment to help set up contract’s storage variables
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address lcdAdress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLength();
        }
        // for (uint256 i = 0; i < tokenAddress.length; i++) {
        //     // s_priceFeeds[tokenAddress[i] = priceFeedAddress[i]];
        // }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address token = tokenAddresses[i];
            address feed = priceFeedAddresses[i];
            if (token == address(0) || feed == address(0)) {
                revert DSCEngine__NotAllowedTokenAddress(); // or a dedicated zero-address error
            }
            //For each token → feed pair, store it in the s_priceFeeds mapping.
            s_priceFeeds[token] = feed;
            //also push the token address to the array
            s_ArrayCollateralTokens.push(tokenAddresses[i]);
        }
        i_lcdAddress = DecentralizedStableCoin(lcdAdress); //saving a reference to the already-deployed DecentralizedStableCoin contract
    }

    ////////////////////////////////////////////////
    ///////////////--EXTERNAL FUNCTIONS---//////////
    ////////////////////////////////////////////////
    //COMBINATION OF depositCollateral + mintDsc functions
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
        ] += amountCollateral; //setting the amount on the s_collateralDeposited mapping
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        //interactions
        //why the IERC20?
        // function transferFrom(address from, address to, uint256 value) external returns (bool);
        //moves tokens from the user to my contract
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

    /**
     * @notice This is how users acquire the stablecoin, they deposit collateral greater than the value of the DSC minted
     * @notice follows CEI Pattern
     * @param amountDSCToMint The amount of DSC to mint
     * @notice they must have more collateral than the minimum threshold
     */
    // 1. check if the collateral is > greater than dsc amount
    function mintDsc(
        uint256 amountDSCToMint
    ) external moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        //if they mint too much 100$ETH > 150$LCD revert
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_lcdAddress.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    //If the value of a user's collateral quickly falls,
    //users will need a way to quickly rectify the collateralization of their LCD.
    function burnDsc() external {}

    function liquidate() external {}

    //View an account's healthFactor
    //healthFactor will be defined as a certain ratio of collateralization a user has for the DSC they've minted.
    //As the value of a user's collateral falls, as will their healthFactor, if no changes to DSC held are made.
    //If a user's healthFactor falls below a defined threshold, the user will be at risk of liquidation.
    function getHealthFactor() external view {}

    ////////////////////////////////////////////////
    ////////--INTERNAL & PRIVATE FUNCTIONS---///////
    ////////////////////////////////////////////////
    //_ to tell this is an internal function
    function _getAcccountInformation(
        address user
    )
        private
        returns (
            uint256 totalDSCAmountMinted,
            uint256 totalCollateralValueInUSD
        )
    {
        totalDSCAmountMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns how close to liquidation user is
     * @notice If a user goes below 1, they can get liquidated
     * @param user The address of the user being checked
     */
    function _healthFactor(address user) private returns (uint256) {
        //get their total LCD minted and total collateral value to compare, value > total DSC minted
        (
            uint256 totalDSCAmountMinted,
            uint256 totalCollateralValueInUSD
        ) = _getAcccountInformation(user);
        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUSD *
            LIQUIDATION_THRESOLD) / 100;

        return
            (collateralAdjustedForThreshold * PRECISION) / totalDSCAmountMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal {
        //check health
        //revert if no
        uint256 useHealthFactor = _healthFactor(user);
        if (useHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(useHealthFactor);
        }
    }

    ////////////////////////////////////////////////
    ////////--GETTERS, view pure FUNCTIONS---///////
    ////////////////////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUSD) {
        //loop thru each collateral token, get the amount hey have dpeosited, map it to the price , to get the usd value
        for (uint256 i = 0; i < s_ArrayCollateralTokens.length; i++) {
            address token = s_ArrayCollateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRICE_PRECISION) * amount) /
            PRECISION;
    }
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
