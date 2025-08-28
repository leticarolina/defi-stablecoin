// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DSCEngine {
    ///what i wanr my contract to do?
    //deposit their collateral
    //redeem their dsc from the collateral
    //burn DSC to have more collateral, our dsc system should be overcollateralized
    //at no point should the value of the all collateral be =< backed value of LCD
    //AKA WE SHOULD ALWys have more collateral
    //liquidate function users can call in  case theoir collateral goes way too down

    //threshold lets say 150%
    //user pays 100 Dollar worth of ETH
    //WE GIvE THEM BACK 50$ of LCD
    //then ETH value goes down to 74$ thats under the 150% threshold
    //so they go undercollaterized, meaning they get liquidated and
    //users can pay their "debt" and get their collateral for a discount?? to remove their previous position and save the protocol
    //another randok user can pay back the 50$ and get all of the collateral of it?
    //so this person just made 24$ based on someone else liquidation?
    //Because our protocol must always be over-collateralized (more collateral must be deposited then DSC is minted),
    //if a user's collateral value falls below what's required to support their minted DSC, they can be liquidated.
    //Liquidation allows other users to close an under-collateralized position

    //   External Functions  //

    function depositCollateralAndMintDsc() external {}
    //This is how users acquire the stablecoin, they deposit collateral greater than the value of the DSC minted
    function depositCollateral() external {}

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
