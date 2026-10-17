// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MUSDVault} from "../src/MUSDVault.sol";
import {StabilityPoolStrategy} from "../src/StabilityPoolStrategy.sol";
import {MockChainlinkAggregator} from "./mocks/MockChainlinkAggregator.sol";

/**
 * @notice Integration test against the REAL MUSD + StabilityPool on Mezo testnet.
 *
 * Run with:
 *   forge test --match-contract StabilityPoolForkTest \
 *     --fork-url https://rpc.test.mezo.org -vvv
 *
 * The whole contract is skipped when not running on a Mezo testnet fork
 * (chain id 31611), so plain `forge test` stays green without network.
 *
 * Fork quirk (documented, not a contract bug): Mezo testnet serves the
 * BTC/USD price via a NATIVE CHAIN PRECOMPILE
 * (0x7b7c000000000000000000000000000000000015) that cannot execute inside a
 * Foundry fork. Since `withdrawFromSP(amount > 0)` requires the protocol's
 * trove-health check (which reads that price), we `vm.etch` a mock
 * Chainlink aggregator over the precompile address returning the live price.
 * On the real testnet no mocking is needed.
 *
 * NOTE: the public testnet RPC can be flaky / rate-limited; retry on failure.
 */
contract StabilityPoolForkTest is Test {
    /// @notice Verified MUSD on Mezo testnet.
    address internal constant MUSD_ADDR =
        0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;

    /// @notice Verified StabilityPool (proxy) on Mezo testnet.
    address internal constant SP_ADDR =
        0x1CCA7E410eE41739792eA0A24e00349Dd247680e;

    /// @notice Mezo's native BTC/USD price precompile (unrunnable in a fork).
    address internal constant PRICE_PRECOMPILE =
        0x7b7c000000000000000000000000000000000015;

    MUSDVault internal vault;
    StabilityPoolStrategy internal strategy;
    address internal user;

    uint256 internal constant ONE = 1e18;

    function setUp() public {
        // Skip everything unless we are on a Mezo testnet fork.
        vm.skip(block.chainid != 31611);

        // Etch a mock Chainlink aggregator over the native price precompile
        // so the MUSD protocol's trove-health check can execute in the fork.
        MockChainlinkAggregator mockFeed = new MockChainlinkAggregator();
        vm.etch(PRICE_PRECOMPILE, address(mockFeed).code);

        vault = new MUSDVault(
            IERC20(MUSD_ADDR),
            address(this),
            "Mezo MUSD Yield Vault",
            "yvMUSD"
        );
        // address(0) -> auto-resolve to the verified testnet pool.
        strategy = new StabilityPoolStrategy(
            MUSD_ADDR,
            address(0),
            address(vault)
        );
        assertEq(
            address(strategy.stabilityPool()),
            SP_ADDR,
            "default SP resolution mismatch"
        );
        vault.addStrategy(address(strategy), 10_000, type(uint256).max);

        user = makeAddr("user");
        deal(MUSD_ADDR, user, 1_000 * ONE);
        assertEq(IERC20(MUSD_ADDR).balanceOf(user), 1_000 * ONE);
    }

    function test_Fork_DepositRebalanceHarvest() public {
        // 1. User deposits MUSD into the vault.
        vm.startPrank(user);
        IERC20(MUSD_ADDR).approve(address(vault), 1_000 * ONE);
        uint256 shares = vault.deposit(1_000 * ONE, user);
        vm.stopPrank();
        assertGt(shares, 0);

        // 2. Keeper rebalances: 100% target allocation flows into the SP.
        vault.rebalance();
        assertEq(
            strategy.totalAssets(),
            1_000 * ONE,
            "compounded SP deposit should equal deposit (no liquidations expected)"
        );
        assertEq(IERC20(MUSD_ADDR).balanceOf(address(vault)), 0);

        // 3. Gains view is readable; harvest with (likely) zero gains is safe.
        strategy.claimableGains(); // must not revert
        vault.harvest();
        assertEq(vault.totalAssets(), 1_000 * ONE);
    }

    /**
     * @notice Withdrawal path against live protocol state.
     *
     * `withdrawFromSP(amount > 0)` is gated by the MUSD protocol itself: it
     * reverts while ANY trove in the system has ICR < MCR. At the time of
     * writing, Mezo testnet has such troves, so SP withdrawals are blocked
     * for everyone (not just this vault). This test therefore accepts both
     * states:
     *  - withdrawals open  -> full redeem works end-to-end;
     *  - withdrawals gated -> our stack surfaces the exact protocol revert.
     */
    function test_Fork_WithdrawReflectsProtocolState() public {
        vm.startPrank(user);
        IERC20(MUSD_ADDR).approve(address(vault), 1_000 * ONE);
        uint256 shares = vault.deposit(1_000 * ONE, user);
        vm.stopPrank();
        vault.rebalance();

        vm.prank(user);
        try vault.redeem(shares, user, user) returns (uint256 out) {
            assertApproxEqAbs(out, 1_000 * ONE, 1e12);
            assertEq(strategy.totalAssets(), 0);
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "StabilityPool: Cannot withdraw while there are troves with ICR < MCR"
            );
        }
    }

    function test_Fork_ClaimRewardsNoop() public {
        vm.prank(address(vault));
        strategy.claimRewards(); // no deposit -> no-op, must not revert
    }
}
