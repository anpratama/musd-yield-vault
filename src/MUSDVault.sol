// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "./IStrategy.sol";
import {BtcValuation} from "./libraries/BtcValuation.sol";

/**
 * @title MUSDVault
 * @notice ERC-4626 auto-yield vault for MUSD (Mezo's Bitcoin-backed stablecoin).
 *
 * Users deposit MUSD and receive vault shares (e.g. `yvMUSD`). The vault
 * allocates the MUSD across registered {IStrategy} adapters according to
 * per-strategy target allocations (basis points) and per-strategy caps.
 *
 * Key behaviors:
 *  - {rebalance}: (owner/keeper) pulls excess from over-allocated strategies
 *    and pushes idle MUSD into under-allocated ones, respecting caps.
 *  - {harvest}: (owner/keeper) claims rewards from every strategy and
 *    compounds claimed MUSD back into the strategies per target allocation.
 *    Native-token rewards (e.g. BTC gains from the Stability Pool) are held
 *    by the vault, not auto-swapped — but since Wave 2 they ARE counted in
 *    {totalAssets} at the BTC/USD feed price (see below), so they accrue
 *    to share price instead of sitting frozen and uncounted (Wave 1 HIGH).
 *  - BTC-gain valuation: pending/held native BTC (in strategies and in the
 *    vault itself) is valued in MUSD via a Chainlink-style BTC/USD feed
 *    ({BtcValuation}). If no feed is configured or the feed is down/stale,
 *    BTC is valued at 0 — conservative, never a guessed price. Note that
 *    redemptions still settle in MUSD: a payout is limited by the vault's
 *    actual MUSD liquidity until held BTC is swapped to MUSD.
 *  - Withdrawals ALWAYS work, even while paused: {_withdraw} automatically
 *    pulls shortfall liquidity from strategies. {pause} is an emergency brake
 *    on deposits and admin fund movements, never on user exits.
 *  - {emergencyWithdrawAll}: (owner) pulls everything back from all strategies
 *    into the vault; callable even while paused.
 *
 * Composability: the share token is a standard ERC-4626 share and can be used
 * as collateral in other DeFi protocols.
 *
 * Security notes (hackathon scope, stated honestly):
 *  - No formal audit. ReentrancyGuard on admin fund-moving functions,
 *    SafeERC20 everywhere, strategy allowlist controlled by owner.
 *  - Strategies are trusted contracts: only register adapters you have
 *    reviewed (a malicious strategy could misreport totalAssets).
 *  - First-depositor inflation: uses OpenZeppelin's default ERC-4626
 *    accounting; a production deployment should add virtual shares/assets or
 *    a minimum initial deposit.
 */
contract MUSDVault is ERC4626, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Mezo's native BTC/USD price precompile (Chainlink-style).
    address public constant MEZO_BTC_USD_FEED =
        0x7b7c000000000000000000000000000000000015;

    /// @notice Mezo testnet chain id.
    uint256 public constant MEZO_TESTNET_CHAIN_ID = 31611;

    /// @notice BTC/USD price feed used to value native BTC held by the
    /// vault (e.g. claimed Stability Pool gains) in {totalAssets}.
    /// address(0) = valuation disabled (held BTC counted as 0).
    address public immutable btcPriceFeed;

    struct StrategyInfo {
        bool active;
        uint256 targetBps;
        uint256 cap;
    }

    /// @notice All registered strategies (including inactive ones).
    address[] public strategyList;

    /// @notice Registry flag per strategy address.
    mapping(address => bool) private _registered;

    /// @notice Per-strategy configuration.
    mapping(address => StrategyInfo) public strategies;

    event StrategyAdded(
        address indexed strategy,
        uint256 targetBps,
        uint256 cap
    );
    event StrategyRemoved(address indexed strategy);
    event AllocationUpdated(address indexed strategy, uint256 targetBps);
    event CapUpdated(address indexed strategy, uint256 cap);
    event StrategyActiveUpdated(address indexed strategy, bool active);
    event Rebalanced(
        address indexed strategy,
        uint256 deposited,
        uint256 withdrawn
    );
    event Harvested(
        address indexed strategy,
        uint256 musdGained,
        uint256 nativeGained
    );
    event StrategyWithdrawal(address indexed strategy, uint256 amount);
    event EmergencyWithdrawal(address indexed strategy, uint256 amount);

    /**
     * @param _musd MUSD token address (NOT hardcoded; injected at deploy).
     * @param _owner Admin (multisig recommended for production).
     * @param _btcPriceFeed BTC/USD feed for valuing held native BTC.
     *        Pass address(0) to auto-resolve to Mezo's native price
     *        precompile on testnet (chain 31611); on other chains
     *        address(0) leaves valuation disabled (BTC counted as 0).
     */
    constructor(
        IERC20 _musd,
        address _owner,
        string memory _name,
        string memory _symbol,
        address _btcPriceFeed
    ) ERC4626(_musd) ERC20(_name, _symbol) Ownable(_owner) {
        require(address(_musd) != address(0), "MUSDVault: zero asset");
        require(_owner != address(0), "MUSDVault: zero owner");
        address feed = _btcPriceFeed;
        if (feed == address(0) && block.chainid == MEZO_TESTNET_CHAIN_ID) {
            feed = MEZO_BTC_USD_FEED;
        }
        btcPriceFeed = feed;
    }

    // ---------------------------------------------------------------------
    // ERC-4626 overrides
    // ---------------------------------------------------------------------

    /// @notice Deposits are blocked while paused; withdrawals stay open.
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice Mints are blocked while paused; withdrawals stay open.
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Vault TVL in MUSD: idle MUSD balance + active strategies'
     * positions (each strategy's totalAssets already includes the MUSD
     * value of its pending BTC gains) + the MUSD value of native BTC held
     * directly by the vault (claimed gains), valued via the BTC/USD feed.
     * Held BTC is valued at 0 if no feed is set or the feed is down/stale.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len; ++i) {
            address s = strategyList[i];
            if (strategies[s].active) total += IStrategy(s).totalAssets();
        }
        total += BtcValuation.musdValueOf(btcPriceFeed, address(this).balance);
        return total;
    }

    /**
     * @dev If idle MUSD is insufficient for a withdrawal, pull the shortfall
     * from strategies (in registration order) before settling. This keeps
     * withdrawals working at all times, including while paused.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle < assets) _pullFromStrategies(assets - idle);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    // ---------------------------------------------------------------------
    // Admin: strategy registry
    // ---------------------------------------------------------------------

    /// @notice Register a new strategy. Owner-only.
    function addStrategy(
        address strategy,
        uint256 targetBps,
        uint256 cap
    ) external onlyOwner {
        require(strategy != address(0), "MUSDVault: zero strategy");
        require(!_registered[strategy], "MUSDVault: already added");
        require(targetBps <= BPS_DENOMINATOR, "MUSDVault: bps too high");
        require(
            _totalTargetBps() + targetBps <= BPS_DENOMINATOR,
            "MUSDVault: bps overflow"
        );
        _registered[strategy] = true;
        strategyList.push(strategy);
        strategies[strategy] = StrategyInfo({
            active: true,
            targetBps: targetBps,
            cap: cap
        });
        emit StrategyAdded(strategy, targetBps, cap);
    }

    /// @notice Update a strategy's target allocation (bps). Owner-only.
    function setAllocation(
        address strategy,
        uint256 targetBps
    ) external onlyOwner {
        require(_registered[strategy], "MUSDVault: unknown strategy");
        uint256 total = _totalTargetBps() -
            strategies[strategy].targetBps +
            targetBps;
        require(total <= BPS_DENOMINATOR, "MUSDVault: bps overflow");
        strategies[strategy].targetBps = targetBps;
        emit AllocationUpdated(strategy, targetBps);
    }

    /// @notice Update a strategy's max allocation cap. Owner-only.
    function setCap(address strategy, uint256 cap) external onlyOwner {
        require(_registered[strategy], "MUSDVault: unknown strategy");
        strategies[strategy].cap = cap;
        emit CapUpdated(strategy, cap);
    }

    /// @notice Activate/deactivate a strategy without removing it. Owner-only.
    /// Inactive strategies are excluded from totalAssets/rebalance/harvest.
    function setStrategyActive(
        address strategy,
        bool active
    ) external onlyOwner {
        require(_registered[strategy], "MUSDVault: unknown strategy");
        strategies[strategy].active = active;
        emit StrategyActiveUpdated(strategy, active);
    }

    /// @notice Remove an empty strategy from the registry. Owner-only.
    function removeStrategy(address strategy) external onlyOwner {
        require(_registered[strategy], "MUSDVault: unknown strategy");
        require(
            IStrategy(strategy).totalAssets() == 0,
            "MUSDVault: strategy not empty"
        );
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len; ++i) {
            if (strategyList[i] == strategy) {
                strategyList[i] = strategyList[len - 1];
                strategyList.pop();
                break;
            }
        }
        delete strategies[strategy];
        delete _registered[strategy];
        emit StrategyRemoved(strategy);
    }

    // ---------------------------------------------------------------------
    // Admin: rebalance & harvest (keeper functions for the hackathon)
    // ---------------------------------------------------------------------

    /**
     * @notice Move funds between strategies toward target allocations,
     * respecting per-strategy caps. Owner-only. Blocked while paused.
     */
    function rebalance() external onlyOwner whenNotPaused nonReentrant {
        uint256 total = totalAssets();
        uint256 len = strategyList.length;
        // Phase 1: pull excess from over-allocated strategies.
        for (uint256 i = 0; i < len; ++i) {
            address s = strategyList[i];
            StrategyInfo memory info = strategies[s];
            if (!info.active) continue;
            uint256 current = IStrategy(s).totalAssets();
            uint256 desired = _desiredAllocation(total, info);
            if (current > desired) {
                uint256 excess = current - desired;
                IStrategy(s).withdraw(excess);
                emit Rebalanced(s, 0, excess);
            }
        }
        // Phase 2: deploy idle MUSD into under-allocated strategies.
        _deployIdle(total);
    }

    /**
     * @notice Claim rewards from every active strategy, then compound claimed
     * MUSD back into strategies per target allocation. Owner-only. Blocked
     * while paused.
     */
    function harvest() external onlyOwner whenNotPaused nonReentrant {
        IERC20 musd = IERC20(asset());
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len; ++i) {
            address s = strategyList[i];
            if (!strategies[s].active) continue;
            uint256 musdBefore = musd.balanceOf(address(this));
            uint256 nativeBefore = address(this).balance;
            IStrategy(s).claimRewards();
            emit Harvested(
                s,
                musd.balanceOf(address(this)) - musdBefore,
                address(this).balance - nativeBefore
            );
        }
        _deployIdle(totalAssets());
    }

    /**
     * @notice Emergency: pull ALL funds from every active strategy back into
     * the vault. Owner-only. Callable even while paused.
     */
    function emergencyWithdrawAll() external onlyOwner nonReentrant {
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len; ++i) {
            address s = strategyList[i];
            if (!strategies[s].active) continue;
            uint256 bal = IStrategy(s).totalAssets();
            if (bal > 0) {
                IStrategy(s).withdraw(bal);
                emit EmergencyWithdrawal(s, bal);
            }
        }
    }

    // ---------------------------------------------------------------------
    // Emergency controls
    // ---------------------------------------------------------------------

    /// @notice Pause deposits, mints, rebalance and harvest. Owner-only.
    /// Withdrawals/redeems remain open so users can always exit.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the vault. Owner-only.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _desiredAllocation(
        uint256 total,
        StrategyInfo memory info
    ) internal pure returns (uint256) {
        uint256 byBps = (total * info.targetBps) / BPS_DENOMINATOR;
        return Math.min(byBps, info.cap);
    }

    /// @dev Deploy idle MUSD into under-allocated strategies.
    function _deployIdle(uint256 total) internal {
        IERC20 musd = IERC20(asset());
        uint256 idle = musd.balanceOf(address(this));
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len && idle > 0; ++i) {
            address s = strategyList[i];
            StrategyInfo memory info = strategies[s];
            if (!info.active) continue;
            uint256 current = IStrategy(s).totalAssets();
            uint256 desired = _desiredAllocation(total, info);
            if (desired > current) {
                uint256 amount = Math.min(desired - current, idle);
                if (amount == 0) continue; // nothing deployable; a 0-amount
                // deposit would revert at the Stability Pool (amount != 0
                // check) once BTC-gain value inflates `desired` past the
                // strategy's MUSD position.
                musd.safeIncreaseAllowance(s, amount);
                IStrategy(s).deposit(amount);
                idle -= amount;
                emit Rebalanced(s, amount, 0);
            }
        }
    }

    /**
     * @dev Pull `shortfall` MUSD from strategies (registration order).
     * Measures what each strategy ACTUALLY delivered: a strategy whose
     * underlying protocol is temporarily blocked (e.g. the Stability Pool
     * gating withdrawals on trove health) may deliver less than requested
     * — possibly 0 — without reverting. The pull then continues to the
     * next strategy, and only fails with this vault's own error if total
     * delivered MUSD cannot cover the shortfall.
     */
    function _pullFromStrategies(uint256 shortfall) internal {
        IERC20 musd = IERC20(asset());
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len && shortfall > 0; ++i) {
            address s = strategyList[i];
            if (!strategies[s].active) continue;
            uint256 bal = IStrategy(s).totalAssets();
            if (bal == 0) continue;
            uint256 take = Math.min(bal, shortfall);
            uint256 idleBefore = musd.balanceOf(address(this));
            IStrategy(s).withdraw(take);
            uint256 got = musd.balanceOf(address(this)) - idleBefore;
            if (got > take) got = take; // defensive: never over-credit
            if (got > 0) emit StrategyWithdrawal(s, got);
            shortfall -= got;
        }
        require(shortfall == 0, "MUSDVault: insufficient liquidity");
    }

    function _totalTargetBps() internal view returns (uint256) {
        uint256 total = 0;
        uint256 len = strategyList.length;
        for (uint256 i = 0; i < len; ++i) {
            total += strategies[strategyList[i]].targetBps;
        }
        return total;
    }

    /// @notice Accept native-token rewards (e.g. BTC gains) forwarded by strategies.
    receive() external payable {}
}
