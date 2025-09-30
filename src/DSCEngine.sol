//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Stablecoin Engine (DSCEngine)
 * @author Leticia Azevedo
 * @notice Users can deposit collateral and mint LCD (LetiCarolinaDollar).
 * at no point should the value of the all collateral be less than backed value of LCD
 * @dev Maintains over-collateralization, liquidation if HF < 1.
 * @dev liquidate function users can call in case their collateral goes way too down
 */
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol"; //interface for Chainlink Price Feeds, takes the address of the price feed as input
import {OracleLib} from "./libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    using OracleLib for AggregatorV3Interface;

    ////////////////////////////////////////////////
    ///////////////----CUSTOM ERRORS------//////////
    ////////////////////////////////////////////////
    error DSCEngine__AmountShouldBeMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLength();
    error DSCEngine__NotAllowedTokenAddress();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthfactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsGood(uint256 healthfactor);
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__RedeemExceedsBalance();
    error DSCEngine__NotEnoughDSC();

    ////////////////////////////////////////////////
    ///////////////---STATE VARIABLES------/////////
    ////////////////////////////////////////////////
    DecentralizedStableCoin private immutable i_lcdAddress; //token contract instance, reference to DecentralizedStableCoin (so the engine can mint/ burn)
    mapping(address token => address priceFeed) private s_priceFeeds; //TokenToPriceFeed, maps each collateral token to its Chainlink price feed.
    mapping(address user => mapping(address token => uint256 amount)) //how much of each token a user deposited
        private s_collateralDeposited; //user address TO A mapping of token Address > amount minted from that token address
    mapping(address user => uint256 amountDSCMinted) s_DSCMinted; //How much each user has borrowed (minted)
    address[] private s_ArrayCollateralTokens; //array to store the chainlink PriceFeed address of collaterals
    uint256 private constant ADDITIONAL_FEED_PRICE_PRECISION = 1e10; //because chainlink price feed is already 8 decimals, turns into 18
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 80; //means we only count 80% of collateral deposited
    uint256 private constant LIQUIDATION_PRECISION = 100; //to do percentage calculations eg 80/100 = 0.8 (80%)
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18; // 1
    uint256 private constant BONUS_LIQUIDATION = 10; // 10% of bonus when paying users debt

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
        // inputs passed during deployment to help set up storage variables
        address[] memory tokenAddresses, //WETH, WBTC
        address[] memory priceFeedAddresses, //Chainlink
        address lcdAdress //DecentralizedStableCoin.sol
    ) {
        //checks if both arrays have the same length.
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLength();
        }
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
     * @notice Mints the stablecoin
     * @notice they must have more collateral than the minimum threshold, follows CEI Pattern.
     * @param amountDSCToMint The amount of DSC tokens users want to get (mint)
     */
    function mintDsc(
        uint256 amountDSCToMint
    ) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint; //s_DSCMinted[user]: the user’s 'debt'
        _revertIfHealthFactorIsBroken(msg.sender); //if they try mint too much eg. 100$ETH > 150$LCD revert, ensure their collateral is healthy after minting.
        bool minted = i_lcdAddress.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice This function combines burns DSC and then redeem users collateral in one transaction
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
    }

    /**
     * @notice If the value of a user's collateral quickly falls, users will need a way to quickly rectify the collateralization of their LCD.
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //backup bcs burning won't really drop health factor
    }

    /**
     * @notice Users can repay someone else’s debt (DSC) on their behalf if undercollateralized, and get rewarded with some of their collateral + 10% LIQUIDATION_BONUS
     * @notice This function working assumes that the protocol will be roughly 125% overcollateralized in order for this to work.
     * @notice A bug would be if the protocol was only 100% collateralized, we wouldn't be able incentive liquidators or to liquidate anyone.
     * Example: if the price of the collateral plummeted before anyone could be liquidated.
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * @param user: The user to liquidate, who is insolvent. Must have a _healthFactor below MIN_HEALTH_FACTOR 1
     * @param debtToCover: The amount of DSC you want to repay/burn to cover the user debt.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        //Checks user health factor
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsGood(startingUserHealthFactor);
        }
        if (i_lcdAddress.balanceOf(msg.sender) < debtToCover) {
            revert DSCEngine__NotEnoughDSC();
        }

        //eg 100dsc debtToCover, 100dsc == HOW MUCH ETH?
        // Given a DSC amount (debtToCover), how much of this collateral token should I take (ETH, BTC, etc.) in return?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromDSC(
            collateral,
            debtToCover
        );

        // 10% bonus: liquidator redeems debt value in collateral + 10%
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            BONUS_LIQUIDATION) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        //The liquidator burns debtToCover DSC on behalf of the insolvent user to reduce their debt and improve HF
        _burnDSC(debtToCover, user, msg.sender);
        //Take totalCollateralToRedeem worth of their ETH/BTC out of the protocol and send it to the liquidator
        //this makes user HF even worse temporarily
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );

        //make sure that the liquidation actually helped, if their HF didn’t improve → revert
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    ////////////////////////////////////////////////
    ////////--INTERNAL & PRIVATE FUNCTIONS---///////
    ////////////////////////////////////////////////
    //_ to tell this is an internal function

    /**
     * @notice Internal function to handle redeeming collateral and checking if the health factor is still safe after that action.
     * @notice For when a user voluntarily withdraws their own collateral or a liquidator redeems collateral from a user who is undercollateralized.
     * @param tokenCollateralAddress The address of the collateral being redeemed (ETH, BTC)
     * @param amountCollateral The amount of collateral user wants to redeem
     * @param from The address where the collateral is being taken from
     * @param to The address where the collateral is being sent to, Can be: The user (normal redeem) or A liquidator (forced liquidation)
     */
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        uint256 balance = s_collateralDeposited[from][tokenCollateralAddress];
        if (amountCollateral > balance) {
            revert DSCEngine__RedeemExceedsBalance();
        }
        s_collateralDeposited[from][tokenCollateralAddress] =
            balance -
            amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        //sending tokens back from the contract to the user (or a liquidator)
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(from);
    }

    /**
     * @notice Burns DSC to reduce the users debt.
     * @param amountDSCToBurn The amount of DSC user wants to burn
     * @param onBehalfOf The address of the user being helped, paying down their debt
     * @param dscFrom The address where the DSC is being taken from to pay down the debt
     * @dev low level func, not to call unless the function calling it is checking health factor
     */
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

    /**
     * @notice Returns uint256 how close to liquidation user is
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

    /**
     * @notice The real calculation comparison the get users health factor
     * @notice Returns the health factor in 18 decimals
     * @param totalDscMinted The users total debt in DSC 18 decimals
     * @param collateralValueInUsd The total collateral value user has in USD
     */
    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max; //returns a good healthFactor so brand-new users aren’t “liquidatable”
        //If collateralValueInUsd is $200, collateralAdjustedForThreshold = 200 * 80 / 100 = 160$
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return
            //healthFactor = (160 * 1e18) / debt in Wei
            (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice All this function does is revert if the Health Factor is less than 1
     * @notice If healthFactor < 1e18 the user can be liquidated
     * @param user The address of the user being checked
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 useHealthFactor = _healthFactor(user);
        if (useHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(useHealthFactor);
        }
    }

    ////////////////////////////////////////////////
    ////////--GETTERS, view pure FUNCTIONS---///////
    ////////////////////////////////////////////////

    /**
     * @notice Gets the total amount of StableCoin minted and the total amount in USD deposited
     */
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
     * @notice Given an user, it returns the total collateral deposited converted to Dollar
     * @dev loop thru each collateral token, get the ETH/BTC amount user have deposited on each collaterals
     * take those amount getUSDValue() for each token.
     * @param totalCollateralValueInUSD The total amount user have deposited in current USD price
     */
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUSD) {
        //loop thru each collateral token, get the amount they have deposited on each token
        //map it to the price, to get the total usd value
        for (uint256 i = 0; i < s_ArrayCollateralTokens.length; i++) {
            address token = s_ArrayCollateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
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
     * @notice Pricing helper to get USD amount of a collateral deposited
     * @param token The token address of the collateral being checked (eth or btc)
     * @param amount The amount of the token in ETH or BTC value (eg 1e18ETH)
     */
    function getUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        // AggregatorV3Interface(<address>) is casting the address to the interface type so can call latestRoundData, getRoundData on that specific deployed feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        //(e8 * e10) * e18 = 36 decimals / e18 division brings it down to 18
        return
            ((uint256(price) * ADDITIONAL_FEED_PRICE_PRECISION) * amount) /
            PRECISION;
    }

    /**
     * @notice Pricing helper to get TOKEN amount of a collateral deposited.
     * @notice Takes X DSC dollars and returns how much ETH is needed to match that value at current price
     * @param token The token address of the collateral being checked (eth or btc)
     * @param dscAmountInWei The amount of dollars in wei (eg. 50e18 50$)
     */
    function getTokenAmountFromDSC(
        address token,
        uint256 dscAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        //(50e18 * 1e18) / (e8 * e10) = e36 dsc amount / e18 current usd price of collateral
        return
            (dscAmountInWei * PRECISION) /
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

    function getDSCMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_ArrayCollateralTokens;
    }

    function liquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function minHealthFactor() external pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    //test
    function getLatestPriceFeed() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        ); //USD/BTC
        (
            uint80 roundId,
            int256 currentPrice,
            ,
            ,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData(); //Grab the price
        require(answeredInRound >= roundId, "incomplete round");

        uint256 adjustedUsdPrice = uint256(currentPrice) * 1e10; //eg. 3000e18 (3k)
        return adjustedUsdPrice;
    }
}
