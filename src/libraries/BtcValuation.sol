// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";

/**
 * @title BtcValuation
 * @notice Values native BTC amounts (18 decimals, as paid by the Mezo
 * Stability Pool) in MUSD terms (18 decimals, $1 peg) using a
 * Chainlink-style BTC/USD price feed.
 *
 * Valuation approach (explicit, no faked prices):
 *   musdValue = btcWei * price / 10^feedDecimals
 * where `price` is the feed's USD-per-BTC answer. BTC and MUSD both use
 * 18 decimals, so no additional scaling is needed.
 *
 * Conservative failure mode: if no feed is configured, the feed call
 * reverts, the answer is non-positive, or the answer is stale
 * (older than {MAX_PRICE_AGE}), the BTC is valued at **0** — never at a
 * guessed price. This keeps `totalAssets()` (and therefore deposits and
 * withdrawals) working even when the oracle is unavailable; BTC gains
 * simply stop contributing to share price until the feed recovers.
 */
library BtcValuation {
    /// @notice Maximum accepted age of a price answer.
    uint256 internal constant MAX_PRICE_AGE = 1 days;

    /**
     * @notice MUSD value of `btcWei` native BTC at the feed's BTC/USD price.
     * Returns 0 when no trustworthy price is available.
     */
    function musdValueOf(
        address feed,
        uint256 btcWei
    ) internal view returns (uint256) {
        if (feed == address(0) || btcWei == 0) return 0;
        try IPriceFeed(feed).decimals() returns (uint8 dec) {
            try IPriceFeed(feed).latestRoundData() returns (
                uint80,
                int256 answer,
                uint256,
                uint256 updatedAt,
                uint80
            ) {
                if (answer <= 0) return 0;
                if (updatedAt == 0) return 0;
                if (updatedAt + MAX_PRICE_AGE < block.timestamp) return 0;
                return (btcWei * uint256(answer)) / (10 ** uint256(dec));
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }
}
