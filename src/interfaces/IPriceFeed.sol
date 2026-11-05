// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Minimal Chainlink AggregatorV3-style price feed interface.
 *
 * On Mezo, the BTC/USD price is served by a native chain precompile at
 * 0x7b7c000000000000000000000000000000000015 which exposes exactly this
 * interface (see StabilityPoolFork.t.sol / MockChainlinkAggregator).
 * Only the functions used by {BtcValuation} are included.
 */
interface IPriceFeed {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
