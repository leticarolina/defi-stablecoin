//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from
    "../../lib/chainlink-evm/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol"; //interface for Chainlink Price Feeds, takes the address of the price feed as input

//interface for Chainlink Price Feeds, takes the address of the price feed as input

/**
 * @title OracleLib
 * @author Leticia Azevedo
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, functions will revert, and render the AZDEngine unusable - this is by design.
 * We want the AZDEngine to freeze if prices become stale.
 * Known issue:
 * So if the Chainlink network explodes or price sinks quick and user have a lot of money locked in the protocol... bad.
 */

//automatically check to see if price is stale
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 1 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
