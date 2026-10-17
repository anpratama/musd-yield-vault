// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategy} from "./IStrategy.sol";

/**
 * @title MockYieldStrategy
 * @notice **TESTNET STRATEGY SIMULATOR — NOT REAL YIELD.**
 *
 * This contract simulates a yield-bearing strategy for demo/testnet use while
 * the Mezo ecosystem matures. It accrues yield linearly over time at a
 * configurable APY (`apyBps`), backed by a reward pool that anyone can fund
 * via {fundRewards} (on testnet: the deployer/keeper).
 *
 * Accounting invariants:
 *  - `totalAssets() == principal + accrued` and is always fully backed by the
 *    contract's MUSD balance (accrual is capped by the funded-but-unclaimed
 *    reward pool).
 *  - {claimRewards} transfers accrued MUSD to the vault and resets accrual.
 *
 * Replace with a real strategy adapter (e.g. {StabilityPoolStrategy}) for any
 * production use. This simulator exists so the vault's rebalance/harvest
 * logic can be demonstrated end-to-end on Mezo testnet.
 */
contract MockYieldStrategy is IStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice MUSD token this strategy accepts.
    IERC20 public immutable musd;

    /// @notice The vault allowed to call deposit/withdraw/claimRewards.
    address public vault;

    /// @notice Simulated APY in basis points (1000 = 10%).
    uint256 public apyBps;

    /// @notice MUSD principal currently deployed in the simulation.
    uint256 public principal;

    /// @notice Accrued but unclaimed simulated yield (MUSD).
    uint256 public accrued;

    /// @notice Timestamp of the last accrual checkpoint.
    uint256 public lastAccrual;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    event VaultUpdated(address indexed vault);
    event ApyUpdated(uint256 apyBps);
    event RewardsFunded(address indexed from, uint256 amount);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event RewardsClaimed(address indexed to, uint256 amount);

    constructor(
        IERC20 _musd,
        address _vault,
        uint256 _apyBps
    ) Ownable(msg.sender) {
        require(address(_musd) != address(0), "MockYieldStrategy: zero musd");
        musd = _musd;
        vault = _vault;
        apyBps = _apyBps;
        lastAccrual = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "MockYieldStrategy: only vault");
        _;
    }

    /// @notice Point the strategy at a (new) vault. Owner-only.
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @notice Update the simulated APY. Owner-only (demo/keeper control).
    function setApyBps(uint256 _apyBps) external onlyOwner {
        _accrue();
        apyBps = _apyBps;
        emit ApyUpdated(_apyBps);
    }

    /**
     * @notice Fund the simulated reward pool with MUSD. Anyone may call this
     * (on testnet the keeper tops it up); without funding, no yield accrues.
     */
    function fundRewards(uint256 amount) external {
        _accrue();
        musd.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(msg.sender, amount);
    }

    /// @inheritdoc IStrategy
    function deposit(uint256 amount) external onlyVault nonReentrant {
        _accrue();
        musd.safeTransferFrom(msg.sender, address(this), amount);
        principal += amount;
        emit Deposited(amount);
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount) external onlyVault nonReentrant {
        _accrue();
        uint256 available = principal + accrued;
        uint256 take = Math.min(amount, available);
        uint256 fromPrincipal = Math.min(take, principal);
        principal -= fromPrincipal;
        accrued -= (take - fromPrincipal);
        if (take > 0) musd.safeTransfer(msg.sender, take);
        emit Withdrawn(take);
    }

    /// @inheritdoc IStrategy
    function totalAssets() external view returns (uint256) {
        return principal + _pendingAccrued();
    }

    /// @inheritdoc IStrategy
    function claimRewards() external onlyVault nonReentrant {
        _accrue();
        uint256 rewards = accrued;
        accrued = 0;
        if (rewards > 0) musd.safeTransfer(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, rewards);
    }

    /// @notice Simulated yield accrued since the last checkpoint (view).
    function pendingRewards() external view returns (uint256) {
        return _pendingAccrued();
    }

    function _pendingAccrued() internal view returns (uint256) {
        if (principal == 0 || apyBps == 0) return accrued;
        uint256 elapsed = block.timestamp - lastAccrual;
        uint256 earn = (principal * apyBps * elapsed) /
            (BPS_DENOMINATOR * SECONDS_PER_YEAR);
        uint256 balance = musd.balanceOf(address(this));
        uint256 committed = principal + accrued;
        uint256 available = balance > committed ? balance - committed : 0;
        if (earn > available) earn = available;
        return accrued + earn;
    }

    function _accrue() internal {
        accrued = _pendingAccrued();
        lastAccrual = block.timestamp;
    }
}
