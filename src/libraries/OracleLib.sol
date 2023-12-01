// SPDX License Identifier: MIT

pragma solidity ^0.8.18;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
@title OracleLib
@notice Library to check that the oracle is behaving correctly, and priceFeed is not stale
@notice If stale, then the oracle should revert, transactions to the oracle should not go through
*/

library OracleLib {
    error OracleLib__PriceIsStale();
    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 _price, uint256 startedAt ,uint256 updatedAt ,uint80 answeredInRound ) = priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) {
            revert OracleLib__PriceIsStale();  
        }
        return (roundId, _price, startedAt, updatedAt, answeredInRound);
    }
}