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
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol"; //interface for Chainlink Price Feeds, takes the address of the price feed as input

//v2.27.0
// ...,,,,,..///////////÷÷÷≥≥≥≥≥≥≤≤≤≤≤≥≥≥

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
    error DSCEngine__HealthFactorIsGood();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////////////////////////////////
    ///////////////---STATE VARIABLES------/////////
    ////////////////////////////////////////////////
    DecentralizedStableCoin private immutable i_lcdAddress; //reference to DecentralizedStableCoin (so the engine can mint/ burn)
    mapping(address token => address priceFeed) private s_priceFeeds; //TokenToPriceFeed, maps each collateral token to its Chainlink price feed.
    mapping(address user => mapping(address token => uint256 amount)) //how much of each token a user deposited
        private s_collateralDeposited; //user address TO A mapping of token Address > amount minted from that token address
    mapping(address user => uint256 amountDSCMinted) s_DSCMinted; //How much each user has borrowed (minted),
    address[] private s_ArrayCollateralTokens; //array to store the PriceFeed address os collaterals
    uint256 private constant ADDITIONAL_FEED_PRICE_PRECISION = 1e10; //because chainlink price feed is already 8 decimals, turns into 18
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //50% means we only count 50% of your collateral as safe collateral
    uint256 private constant LIQUIDATION_PRECISION = 100; //denominator (so 50/100 = 0.5 = 50%)
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant BONUS_LIQUIDATION = 10;

    ////////////////////////////////////////////////
    ///////////////---EVENTS------//////////////////
    ////////////////////////////////////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
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
    ///////////////----CONSTRUCTOR------////////////
    ////////////////////////////////////////////////
    constructor(
        // inputs passed during deployment to help set up contract’s storage variables
        address[] memory tokenAddresses, //WETH, WBTC
        address[] memory priceFeedAddresses, //Chainlink
        address lcdAdress
    ) {
        //checks if both arrays have the same length.
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
                revert DSCEngine__NotAllowedTokenAddress();
            }
            //For each token → feed pair, store it in the s_priceFeeds mapping.
            s_priceFeeds[token] = feed;
            //also push the token address to the s_ArrayCollateralTokens array
            s_ArrayCollateralTokens.push(tokenAddresses[i]);
        }
        i_lcdAddress = DecentralizedStableCoin(lcdAdress); //saving a reference to the already-deployed DecentralizedStableCoin contract
    }

    ////////////////////////////////////////////////
    ////////--EXTERNAL/PUBLIC FUNCTIONS---//////////
    ////////////////////////////////////////////////
    /**
     * @notice This function is the combination of depositCollateral + mintDsc functions so user doesn't have to call each separately
     * @notice it will deposit the Collateral and mint the DSC in one transaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDSCToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDSCToMint);
    }

    /**
     * @notice This is how users acquire the stablecoin, they deposit collateral greater than the value of the DSC minted
     * @notice follows CEI Pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        //effect
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral; //setting the amount deposited on the s_collateralDeposited mapping
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        //interactions
        //why the IERC20? This requires the user to call approve(DSCEngine, amount) on the token first (outside contract).
        //User flow is Approve → depositCollateral
        // function .transferFrom(address from, address to, uint256 value) external returns (bool);
        //moves tokens from the user to my contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice This function burns DSC and then redeem users collateral in one transaction
     * @param amountDSCToBurn The amount of DSC to burn
     */
    function burnDscAndRedeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        burnDsc(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral); //already check health factor
    }

    /**
     * @notice This function allows users to return DSC to the protocol in exchange for their underlying collateral
     * @notice In order for them to redeem Collateral, the health factor must be greater than 1 after collateral is pulled
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        // _revertIfHealthFactorIsBroken(msg.sender);
        //1. get health factor
        //2. get collateral value in USD
        //3. get DSC Value
        //4. get Collateral value after redeeming
        //5. get DSC value after redeeming
        //6. check health factor
        //7. redeem collateral
    }

    /**
     * @notice This is how users acquire the stablecoin, they deposit collateral greater than the value of the DSC minted
     * @notice follows CEI Pattern
     * @param amountDSCToMint The amount of DSC to mint
     * @notice they must have more collateral than the minimum threshold
     */
    // 1. check if the collateral is > greater than dsc amount
    function mintDsc(
        uint256 amountDSCToMint
    ) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint; //s_DSCMinted[user]: the user’s 'debt'
        _revertIfHealthFactorIsBroken(msg.sender); //if they mint too much eg. 100$ETH > 150$LCD revert, ensure their collateral is strong enough after minting.
        bool minted = i_lcdAddress.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    //If the value of a user's collateral quickly falls,
    //users will need a way to quickly rectify the collateralization of their LCD.
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //backup bcs burning won't really drop health factor
    }

    /**
     * @notice Follows CEI, You can partially liquidate a user and get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice A bug would be if the protocol was only 100% collateralized, we wouldn't be able incentive liquidators or to liquidate anyone.
     * Example: if the price of the collateral plummeted before anyone could be liquidated.
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        //Checks user health factor
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsGood();
        }
        //i want to burn the user DSC and take their collateral
        //eg bad user: 140ETH, 100dsc Debt to cover
        //100dsc == HOW MUCH ETH? Collateral?
        //chainlink will provide the real-time asset price data to accurately value collateral and calculate liquidation amounts.
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(
            collateral,
            debtToCover
        );
        //// 10% bonus: liquidator redeems debt value in collateral + 10%
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            BONUS_LIQUIDATION) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDSC(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ////////////////////////////////////////////////
    ////////--INTERNAL & PRIVATE FUNCTIONS---///////
    ////////////////////////////////////////////////
    //_ to tell this is an internal function

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        uint256 balance = s_collateralDeposited[from][
            tokenCollateralAddress
        ] -= amountCollateral;
        if (amountCollateral > balance)
            revert DSCEngine__AmountShouldBeMoreThanZero();
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(from);
    }

    //low level internal func, not to call unless the function calling it is checking heath factor
    //onBehalfOf whose user debt are we paying down?
    //dscFrom where we are getting the dsc to burn from
    function _burnDSC(
        uint256 amountDSCToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        //first we take the DSC amount from user, bring to our contract and then we burn after
        bool success = i_lcdAddress.transferFrom(
            dscFrom,
            address(this),
            amountDSCToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed(); //unreachble
        }
        i_lcdAddress.burn(amountDSCToBurn);
    }

    function _getAcccountInformation(
        address user
    )
        private
        view
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
    function _healthFactor(address user) private view returns (uint256) {
        //get their total LCD minted and total collateral value to compare, value > total DSC minted
        (
            uint256 totalDSCAmountMinted,
            uint256 totalCollateralValueInUSD
        ) = _getAcccountInformation(user);
        return
            _calculateHealthFactor(
                totalDSCAmountMinted,
                totalCollateralValueInUSD
            );
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max; //brand-new users aren’t “liquidatable”
        //If collateral is $200 collateralAdjustedForThreshold = 200 * 50 / 100 = 100$ (protocol: We treat the $200 as if it were only $100)
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return
            //healthFactor = (collateralAdjustedForThreshold $100 * 1e18) / debt
            (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 useHealthFactor = _healthFactor(user);
        //If healthFactor < 1e18 the user can be liquidated.
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
        //loop thru each collateral token, get the amount they have deposited, map it to the price , to get the usd value
        for (uint256 i = 0; i < s_ArrayCollateralTokens.length; i++) {
            address token = s_ArrayCollateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice View an account's healthFactor, as the value of a user's collateral falls, will their healthFactor
     * @notice If a user's healthFactor falls below 1 threshold, the user will be at risk of liquidation.
     * @param user The address of the user being checked
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /**
     * @notice Pricing helper to get USD amount of a collateral
     * @param token The address of the user being checked
     * @param amount The address of the user being checked
     */
    function getUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        // AggregatorV3Interface(<address>) is casting the address to the interface type so can call latestRoundData, getRoundData on that specific deployed feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        //Uses Chainlink latestRoundData() and normalizes decimals
        (, int256 price, , , ) = priceFeed.latestRoundData();
        //(uint256(price) * ADDITIONAL_FEED_PRICE_PRECISION) * amount) = 36 decimals / division brings it down to 18
        return
            ((uint256(price) * ADDITIONAL_FEED_PRICE_PRECISION) * amount) /
            PRECISION;
    }

    //If I want X dollars worth of TOKEN, how many TOKEN units is that?
    function getTokenAmountFromUSD(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRICE_PRECISION);
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAcccountInformation(user);
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralDeposited(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_ArrayCollateralTokens;
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
