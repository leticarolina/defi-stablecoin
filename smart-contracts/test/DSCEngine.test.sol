// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {HelperConfig} from "../script/DeployDSC.s.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AggregatorV3Interface} from "../lib/chainlink-evm/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {DSCFailMock} from "./mocks/DSCFailMock.sol";
import {ERC20FailMock} from "./mocks/ERC20FailMock.sol";
import {OracleLib} from "./../src/libraries/OracleLib.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer; //so tests mirror real deployment
    DecentralizedStableCoin dsc; //The ERC-20 stablecoin contract
    DSCEngine dsce;
    HelperConfig config;

    //from helper config
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user"); //mock user
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public AMOUNT_COLLATERAL_DEPOSITED = 10 ether;
    uint256 public INITIAL_BALANCE = 30 ether;
    uint256 public MINTED_DSC_AMOUNT = 20000e18;
    address[] public tokenAddresses; // constructor takes two parallel arrays
    address[] public priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig(); //returning the mock price feeds hardcoded in HelperConfig
        ERC20Mock(weth).mint(USER, INITIAL_BALANCE); //gives/mint some WETH tokens into USER balance son can deposit them in tests
        ERC20Mock(weth).mint(LIQUIDATOR, INITIAL_BALANCE); //Pretend the wallet already has ETH
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        //Approval is needed because depositCollateral() uses transferFrom, user must first allow the DSCEngine to pull their tokens
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSITED);
        // moves the collateral (mock WETH) from USER into the DSCEngine contract and updates the mapping
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL_DEPOSITED);
        vm.stopPrank();
        _;
    }

    modifier mintsStableCoin() {
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT);
        vm.stopPrank();
        _;
    }

    ////////////////////////////////////////////////
    /////////----CONSTRUCTOR TEST------/////////////
    ////////////////////////////////////////////////
    //test_<unitUnderTest>_<stateOrCondition>_<expectedOutcome/Behaviour>

    function test_constructor_reverts_ifTokenLengthDoesntMatchPriceFeeds()
        public
    {
        tokenAddresses.push(weth); // purposely make the arrays unequal length
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressAndPriceFeedMustBeTheSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc)); //try to deploy
        //Without this test, someone can accidentally deploy DSCEngine with mismatched arrays, and mappings would break.
    }

    function test_constructor_revert_ifTokenOrPriceFeedAddressIsZero() public {
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        tokenAddresses.push(address(0));
        tokenAddresses.push(address(0));

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedTokenAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////////////////////////////
    //////////----PRICE FEED TESTS------////////////
    ////////////////////////////////////////////////

    function test_getUSDValue_returnsCorrectConversionResult() public view {
        // 15e18 * 3,000/ETH (hard coded) = 45,000e18
        // didn’t set the price here because it was already set when the mock oracle was deployed in HelperConfig
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 45000e18;
        uint256 actualUsd = dsce.getUSDValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test_getTokenAmountFromDSC_returnsCollateralAmount() public view {
        //270k / btcPrice 90k = 3BTC
        uint256 dscAmount = 270000e18; //minted
        uint256 expectedBtcCollateral = 3e18; //my collateral value given the current usd
        uint256 collateralAmountResult = dsce.getTokenAmountFromDSC(
            wbtc,
            dscAmount
        ); //90000000000000000000
        assertEq(expectedBtcCollateral, collateralAmountResult);
    }

    ////////////////////////////////////////////////
    /////////----DEPOSIT COLLATERAL TEST------//////
    ////////////////////////////////////////////////
    function test_depositCollateral_reverts_IfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSITED);
        vm.expectRevert(
            DSCEngine.DSCEngine__AmountShouldBeMoreThanZero.selector
        );
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_depositCollateral_reverts_WhenDepositUnapprovedCollateral()
        public
    {
        address bnbCollateralUnapproved = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52;
        // ERC20Mock randomToken = new ERC20Mock(); //can also just deploy new randon erc20
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSITED); //Since the revert happens before touching transfer logic, the approval line is irrelevant.
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedTokenAddress.selector);
        dsce.depositCollateral(
            bnbCollateralUnapproved,
            AMOUNT_COLLATERAL_DEPOSITED
        );
    }

    function test_depositCollateral_UpdatesStateAndEmitEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSITED);
        vm.expectEmit(true, true, true, true); //set expectation before the call depositCollateral
        emit DSCEngine.CollateralDeposited(
            USER,
            weth,
            AMOUNT_COLLATERAL_DEPOSITED
        );
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL_DEPOSITED);
        vm.stopPrank();

        // 1) mapping updated
        assertEq(
            dsce.getCollateralDeposited(USER, weth),
            AMOUNT_COLLATERAL_DEPOSITED
        );

        // 2) engine holds tokens
        //weth in test is just an address (the deployed mock ERC20 contract) To call balanceOf() need an ERC20 interface at that address
        assertEq(
            ERC20Mock(weth).balanceOf(address(dsce)),
            AMOUNT_COLLATERAL_DEPOSITED
        );

        // 3) user spent tokens
        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            INITIAL_BALANCE - AMOUNT_COLLATERAL_DEPOSITED
        );

        // 4) no debt minted yet
        (uint256 minted, ) = dsce.getAccountInformation(USER);
        assertEq(minted, 0);
    }

    function test_depositCollateral_revertsOnTransferFail() public {
        // Arrange
        ERC20FailMock badCollateral = new ERC20FailMock(1000e18); //mock erc20 that always fails transfers

        tokenAddresses.push(address(badCollateral));
        priceFeedAddresses.push(ethUsdPriceFeed); // reuse existing price feed

        DSCEngine dsceWithBadToken = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        ); // deploy new DSCEngine with the bad token, otherwise address won't be allowed

        // Give USER some "badCollateral"
        badCollateral.transfer(USER, 100e18);

        vm.startPrank(USER);
        badCollateral.approve(address(dsceWithBadToken), 100e18); //approve DSCEngine

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsceWithBadToken.depositCollateral(address(badCollateral), 100e18);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////
    /////////////----MINT DSC TEST------////////////
    ////////////////////////////////////////////////

    function test_mintDsc_revertsOnZero() public {
        vm.expectRevert(
            DSCEngine.DSCEngine__AmountShouldBeMoreThanZero.selector
        );
        dsce.mintDsc(0);
    }

    function test_mintDsc_revertsIfHealthWouldBreak()
        public
        depositedCollateral
    {
        //Setup: 10ETH AMOUNT_COLLATERAL_DEPOSITED deposited ($30,000k collateral), adjusted 80% => $24.000
        uint256 mintAmount = 25000e18;
        uint256 collateralUsd = dsce.getAccountCollateralValue(USER); //24000e18
        uint256 currentDebt = dsce.getDSCMinted(USER); // likely 0 here
        // HF the engine will compute after adding the new debt
        uint256 expectedHF = dsce.calculateHealthFactor(
            currentDebt + mintAmount,
            collateralUsd
        );
        vm.startPrank(USER);
        // Try to mint more than adjusted collateral -> revert
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHF
            )
        );
        dsce.mintDsc(mintAmount);
        vm.stopPrank();
    }

    function test_mintDsc_recordsDebtMintAndEmit() public depositedCollateral {
        // $30,000 collateral, adjusted = $24,000

        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.DSCMinted(USER, MINTED_DSC_AMOUNT);

        dsce.mintDsc(MINTED_DSC_AMOUNT);
        vm.stopPrank();

        (uint256 minted, ) = dsce.getAccountInformation(USER);

        // Assertions
        assertEq(minted, MINTED_DSC_AMOUNT);
        assertEq(dsc.balanceOf(USER), MINTED_DSC_AMOUNT);
    }

    function test_mintDsc_revertsOnMintFail() public {
        // Arrange
        DSCFailMock badDsc = new DSCFailMock();

        tokenAddresses.push(weth); // normal WETH mock collateral
        priceFeedAddresses.push(ethUsdPriceFeed);

        DSCEngine badEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(badDsc)
        );

        // USER deposits collateral
        vm.startPrank(USER);
        ERC20Mock(weth).approve(
            address(badEngine),
            AMOUNT_COLLATERAL_DEPOSITED
        );
        badEngine.depositCollateral(weth, AMOUNT_COLLATERAL_DEPOSITED);

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        badEngine.mintDsc(MINTED_DSC_AMOUNT); // should fail because badEngine.mint() always returns false
        vm.stopPrank();
    }

    ////////////////////////////////////////////////
    /////////----DEPOSIT+MINT COMBO TEST------//////
    ////////////////////////////////////////////////
    function test_depositAndMint_comboWorks() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL_DEPOSITED);
        dsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL_DEPOSITED,
            MINTED_DSC_AMOUNT
        );
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        assertEq(totalDscMinted, MINTED_DSC_AMOUNT);
        // 10ETH deposited * 3k ETH_USD_PRICE =
        assertEq(collateralValueInUsd, 30000e18);
        assertEq(dsc.balanceOf(USER), MINTED_DSC_AMOUNT);
    }

    function test_burnDscAndRedeemCollateral_comboWorks()
        public
        depositedCollateral
        mintsStableCoin
    {
        // Setup: USER deposits 30k > 24k collateral and mints 20K DSC

        // Check initial state
        (
            uint256 totalDscMintedBefore,
            uint256 collateralValueInUsdBefore
        ) = dsce.getAccountInformation(USER);

        uint256 dscToBurn = 5000e18;
        uint256 collateralToRedeem = dsce.getTokenAmountFromDSC(
            weth,
            dscToBurn
        ); //return is in Token Amount
        uint256 usdValueFromRedemption = dsce.getUSDValue(
            weth,
            collateralToRedeem
        ); //returns in USD

        vm.startPrank(USER); // USER burns DSC and redeems collater
        dsc.approve(address(dsce), dscToBurn);
        dsce.burnDscAndRedeemCollateral(weth, collateralToRedeem, dscToBurn);
        vm.stopPrank();

        // Check final state
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        //asserts
        assertEq(totalDscMinted, totalDscMintedBefore - dscToBurn); // 20k - 5k = 15k DSC left
        assertEq(dsc.balanceOf(USER), MINTED_DSC_AMOUNT - dscToBurn); // 15k DSC left in wallet

        assertEq(
            collateralValueInUsd,
            collateralValueInUsdBefore - usdValueFromRedemption
        ); // all in USD
        assertEq(
            dsce.getCollateralDeposited(USER, weth),
            AMOUNT_COLLATERAL_DEPOSITED - collateralToRedeem
        ); //all in token units (WETH): 10ETH, 10ETH - redeemed WETH amount = WETH left
    }

    ////////////////////////////////////////////////
    /////////////----BURN DSC TEST------////////////
    ////////////////////////////////////////////////

    function test_burnDsc_revertsOnZero() public {
        vm.expectRevert(
            DSCEngine.DSCEngine__AmountShouldBeMoreThanZero.selector
        );
        dsce.burnDsc(0);
    }

    function test_burnDsc_reducesDebtSupplyAndEmitsEvent()
        public
        depositedCollateral
    {
        uint256 burnDscAmount = 5000e18;

        vm.startPrank(USER);

        dsce.mintDsc(MINTED_DSC_AMOUNT); //20k
        dsc.approve(address(dsce), burnDscAmount);

        // Expect the DSCBurned event
        vm.expectEmit(true, true, true, true);
        emit DSCEngine.DSCBurned(burnDscAmount, USER, USER);

        dsce.burnDsc(burnDscAmount); //burns 5k, should be 15k left
        vm.stopPrank();

        (uint256 minted, ) = dsce.getAccountInformation(USER);

        assertEq(minted, 15000e18);
        assertEq(dsc.totalSupply(), 15000e18); // since only USER minted
    }

    ////////////////////////////////////////////////
    /////////----REDEEM COLLATERAL TEST------///////
    ////////////////////////////////////////////////
    function test_redeemCollateral_revertsWhenExceedsBalance()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__RedeemExceedsBalance.selector);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL_DEPOSITED + 1);
        vm.stopPrank();
    }

    function test_redeemCollateral_updatesStateAndBalances()
        public
        depositedCollateral
    {
        uint256 collateralRedeemed = 1 ether;
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, collateralRedeemed);
        vm.stopPrank();

        assertEq(
            dsce.getCollateralDeposited(USER, weth),
            AMOUNT_COLLATERAL_DEPOSITED - collateralRedeemed
        );
        assertEq(
            ERC20Mock(weth).balanceOf(address(dsce)),
            AMOUNT_COLLATERAL_DEPOSITED - collateralRedeemed
        );
        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            (INITIAL_BALANCE - AMOUNT_COLLATERAL_DEPOSITED) + collateralRedeemed
        );
    }

    function test_redeemCollateral_revertsIfHFWouldBreak()
        public
        depositedCollateral
    {
        // Collateral deposited $30.000 (adjusted $24,000). Mint $20.000 -> HF = 1.2

        // Try to redeem 2 WETH ($6k raw -> $4.8k adjusted lost)
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT); //20k
        // uint256 hf = dsce.getHealthFactor(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                9.6e17
            )
        );
        dsce.redeemCollateral(weth, 2 ether); //breaks HF
        vm.stopPrank();
    }

    ////////////////////////////////////////////////
    ////////////----HEALTH FACTOR MATH ------///////
    ////////////////////////////////////////////////
    function test_calculateHealthFactor_math() public pure {
        // collateral 200e18 -> adjusted 160e18 (80%)
        // debt 100e18 => HF = 1.6e18
        uint256 collateralUsd = 200e18;
        uint256 debt = 100e18;
        uint256 adjusted = (collateralUsd * 80) / 100; //160
        uint256 expectedHF = (adjusted * 1e18) / debt; //160 % 100
        expectedHF; // silence warnings
    }

    ////////////////////////////////////////////////
    ////////////----LIQUIDATION  ------////////////
    ////////////////////////////////////////////////
    function test_liquidate_revertsIfUserHealthy() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT); //20k
        uint256 hf = dsce.getHealthFactor(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsGood.selector,
                hf
            )
        );
        dsce.liquidate(weth, USER, 100e18);
        vm.stopPrank();
    }

    function test_liquidate_reverts_whenLiquidatorDoesntHaveEnoughDSC()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2400e8); //PRICE DROP

        vm.startPrank(LIQUIDATOR);
        //tries to liquate without having enough DSC Minted
        dsc.approve(address(dsce), 10000e18);
        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughDSC.selector);
        dsce.liquidate(address(weth), USER, 10000e18); //debtToCover = 10k DSC
        vm.stopPrank();
    }

    function test_liquidate_reverts_ifLiquidationDoesntImproveHealthFactor()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT); //20k debt of collateral
        vm.stopPrank();
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2400e8); //user has now 19.200 adj collateral and 20k debt

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), INITIAL_BALANCE);
        dsce.depositCollateral(weth, INITIAL_BALANCE);
        dsce.mintDsc(10000e18);
        dsc.approve(address(dsce), 1000e18);
        vm.expectRevert();
        dsce.liquidate(address(weth), USER, 1000e18); //debtToCover = 1k DSC only pays a little
        vm.stopPrank();
    }

    function test_liquidate_worksHappyPath() public depositedCollateral {
        // 1. USER deposits 10 ETH (~$30,000), mints 20,000 DSC => HF (safe)
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT); //20k debt of collateral
        vm.stopPrank();

        // 2. Simulate market crash, USER HF = 0.96 (liquidatable)
        //ethUsdPriceFeed is stored as an address pointing to a deployed mock
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(2400e8); //user has now 19.200 adj collateral and 20k debt

        // 3. LIQUIDATOR mints DSC, approves, and calls liquidate
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), INITIAL_BALANCE); //Allows the dsce to pull WETH from the liquidator’s wallet
        dsce.depositCollateral(weth, INITIAL_BALANCE); //deposited entire balance
        dsce.mintDsc(10000e18); // now liquidator has DSC to burn in tests
        dsc.approve(address(dsce), 10000e18); //Allows contract to pull DSC from the liquidator’s wallet when he calls liquidate
        dsce.liquidate(address(weth), USER, 10000e18); //debtToCover = 10k DSC
        vm.stopPrank();

        uint256 userDebt = dsce.getDSCMinted(USER);
        uint256 newHF = dsce.getHealthFactor(USER);
        uint256 tokenAmountFromDebtCovered = dsce.getTokenAmountFromDSC(
            weth,
            10000e18
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * 10) / 100; // 10%
        uint256 expectedCollateralReceived = tokenAmountFromDebtCovered +
            bonusCollateral;
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 liquidatorHF = dsce.getHealthFactor(LIQUIDATOR);

        // 4. Assert:
        assertEq(userDebt, 10000e18); // debt reduced
        assertGt(newHF, 1e18); // HF improved
        assertEq(liquidatorWethBalance, expectedCollateralReceived); // got some ETH as reward
        assertGt(liquidatorHF, 1e18); // liquidator is solvent
    }

    ////////////////////////////////////////////////
    ////////////----GETTERS TESTS ------////////////
    ////////////////////////////////////////////////

    function test_getMinHealthFactor_returnsConstant() public view {
        uint256 minHF = dsce.getMinHealthFactor();
        assertEq(minHF, 1e18);
    }

    function test_getHealthFactor_maxIfNoDebt() public view {
        uint256 hf = dsce.getHealthFactor(USER);
        assertEq(hf, type(uint256).max);
    }

    function test_getCollateralTokens_returnsArray() public view {
        address[] memory tokens = dsce.getCollateralTokens();
        //HelperConfig deploys with WETH + WBTC
        assertEq(tokens.length, 2);
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    ////////////////////////////////////////////////
    ////////----DecentralizedStableCoin ------//////
    ////////////////////////////////////////////////

    function test_mint_revertsIfZeroAddress() public {
        vm.startPrank(address(dsce)); // engine is owner
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__NotZeroAddress
                .selector
        );
        dsc.mint(address(0), 100e18);
        vm.stopPrank();
    }

    function test_mint_revertsIfZeroAmount() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(
            DecentralizedStableCoin.DecentralizedStableCoin__ZeroAmount.selector
        );
        dsc.mint(USER, 0);
        vm.stopPrank();
    }

    function test_burn_revertsIfZeroAmount() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(
            DecentralizedStableCoin.DecentralizedStableCoin__ZeroAmount.selector
        );
        dsc.burn(0);
        vm.stopPrank();
    }

    function test_burn_revertsIfExceedsBalance() public {
        vm.startPrank(address(dsce));
        // USER has 0 tokens, so trying to burn should revert
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__BurnAmountExceedsBalance
                .selector
        );
        dsc.burn(100e18);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////
    ////////////----ORACLE LIBRARY ------///////////
    ////////////////////////////////////////////////
    function test_stalePriceReverts() public {
        // arrange
        MockV3Aggregator mock = new MockV3Aggregator(8, 3000e18);

        // simulate old update (set updatedAt way in the past)
        vm.warp(block.timestamp + 2 hours); // move forward 2 hours

        // act/assert
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(
            AggregatorV3Interface(address(mock))
        ); // library expects an interface type (AggregatorV3Interface)
    }
}
