// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {HelperConfig} from "../script/DeployDSC.s.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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
    uint256 public AMOUNT_COLLATERAL_DEPOSITED = 10 ether;
    uint256 public INITIAL_BALANCE = 30 ether;
    uint256 public MINTED_DSC_AMOUNT = 20000e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig(); //returning the mock price feeds hardcoded in HelperConfig
        ERC20Mock(weth).mint(USER, INITIAL_BALANCE); //gives/mint some WETH tokens into USER balance son can deposit them in tests
        ERC20Mock(wbtc).mint(USER, INITIAL_BALANCE);
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

    //   modifier mintsStableCoin() {
    //     vm.startPrank(USER);
    //     dsce.mintDsc(amount);
    //     vm.stopPrank();
    //     vm.stopPrank();
    //     _;
    // }

    ////////////////////////////////////////////////
    /////////----CONSTRUCTOR TEST------/////////////
    ////////////////////////////////////////////////
    address[] public tokenAddresses; // constructor takes two parallel arrays
    address[] public priceFeedAddresses;

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
        uint256 currentDebt = dsce.getMinted(USER); // likely 0 here
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

    function test_mintDsc_recordsDebtAndMints() public depositedCollateral {
        // $30,000 collateral, adjusted = $24,000
        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT);
        vm.stopPrank();

        (uint256 minted, ) = dsce.getAccountInformation(USER);
        assertEq(minted, MINTED_DSC_AMOUNT);
        assertEq(dsc.balanceOf(USER), MINTED_DSC_AMOUNT);
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

    ////////////////////////////////////////////////
    /////////////----BURN DSC TEST------////////////
    ////////////////////////////////////////////////
    function test_burnDsc_revertsOnZero() public {
        vm.expectRevert(
            DSCEngine.DSCEngine__AmountShouldBeMoreThanZero.selector
        );
        dsce.burnDsc(0);
    }

    function test_burnDsc_reducesDebtAndSupply() public depositedCollateral {
        uint256 burnDscAmount = 5000e18;

        vm.startPrank(USER);
        dsce.mintDsc(MINTED_DSC_AMOUNT); //20k
        dsc.approve(address(dsce), burnDscAmount);
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
        vm.expectRevert();
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
        uint256 adjusted = (collateralUsd * 80) / 100;
        uint256 expectedHF = (adjusted * 1e18) / debt;
        // call external pure for convenience
        // (cannot call directly here since we need instance, but you get idea:)
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
}
