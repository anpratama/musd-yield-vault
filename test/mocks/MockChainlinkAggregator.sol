// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Test-only Chainlink-style aggregator mock.
 *
 * Used ONLY in fork tests: Mezo testnet serves the BTC/USD price through a
 * native chain precompile at 0x7b7c...0015, which cannot execute inside a
 * Foundry fork. Tests `vm.etch` this mock over the precompile address so the
 * MUSD protocol's price/trove-health checks can run. `updatedAt` always
 * returns the current block timestamp so the feed never looks stale.
 *
 * Price returned mirrors the live testnet price (~$81,451, 8 decimals).
 */
contract MockChainlinkAggregator {
    int256 internal constant PRICE = 81_451_376_800; // 8 decimals

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "BTC/USD mock for fork tests";
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, PRICE, block.timestamp, block.timestamp, 1);
    }
}
