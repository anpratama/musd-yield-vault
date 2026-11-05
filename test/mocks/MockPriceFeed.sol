// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Test-only configurable Chainlink-style BTC/USD price feed.
 * Price, staleness and failure are all settable so valuation edge cases
 * (feed down, stale answer, zero price) can be exercised in unit tests.
 * Default: $100,000.00 per BTC, 8 decimals, fresh.
 */
contract MockPriceFeed {
    int256 public price = 100_000 * 1e8; // $100,000.00, 8 decimals
    uint8 public feedDecimals = 8;
    uint256 public updatedAt;
    bool public broken;

    constructor() {
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function setBroken(bool _broken) external {
        broken = _broken;
    }

    /// @notice Re-stamp the answer as fresh at the current block time.
    function refresh() external {
        updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        require(!broken, "MockPriceFeed: down");
        return feedDecimals;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 _updatedAt,
            uint80 answeredInRound
        )
    {
        require(!broken, "MockPriceFeed: down");
        return (1, price, updatedAt, updatedAt, 1);
    }
}
