// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IStrategy} from "./IStrategy.sol";
import {IStabilityPool} from "./interfaces/IStabilityPool.sol";

/**
 * @title StabilityPoolStrategy
 * @notice Real yield strategy adapter for the MUSD Stability Pool on Mezo.
 *
 * Flow:
 *  - {deposit}: pulls MUSD from the vault, approves the Stability Pool and
 *    calls `provideToSP`. Any BTC collateral gains that had accrued are sent
 *    by the pool to this strategy as native tokens and are forwarded to the
 *    vault.
 *  - {withdraw}: calls `withdrawFromSP(amount)`. Note the pool requires no
 *    under-collateralized troves to remain when withdrawing a non-zero amount;
 *    this is a protocol-level constraint, not something this adapter can
 *    bypass.
 *  - {claimRewards}: calls `withdrawFromSP(0)`, which (per the pool's
 *    implementation) skips the trove check and claims only the accumulated
 *    native BTC collateral gains, leaving the MUSD deposit untouched. Gains
 *    are forwarded to the vault. A no-op when there is no deposit.
 *  - {totalAssets}: the strategy's compounded MUSD deposit in the pool. Note
 *    this can DECREASE after liquidations (MUSD is burned to offset debt);
 *    the depositor is compensated with BTC gains instead.
 *
 * The Stability Pool address may be passed explicitly, or left as
 * `address(0)` to auto-resolve to the verified Mezo testnet deployment when
 * `block.chainid == 31611`.
 */
contract StabilityPoolStrategy is IStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Verified Mezo testnet StabilityPool (proxy) address.
    address public constant MEZO_TESTNET_STABILITY_POOL =
        0x1CCA7E410eE41739792eA0A24e00349Dd247680e;

    /// @notice Mezo testnet chain id.
    uint256 public constant MEZO_TESTNET_CHAIN_ID = 31611;

    /// @notice MUSD token accepted by this strategy.
    IERC20 public immutable musd;

    /// @notice The Stability Pool this strategy deposits into.
    IStabilityPool public immutable stabilityPool;

    /// @notice The vault allowed to call deposit/withdraw/claimRewards.
    address public vault;

    event VaultUpdated(address indexed vault);
    event DepositedToSP(uint256 amount);
    event WithdrawnFromSP(uint256 requested, uint256 musdReceived);
    event RewardsClaimed(address indexed to, uint256 nativeGains);

    constructor(
        address _musd,
        address _stabilityPool,
        address _vault
    ) Ownable(msg.sender) {
        require(_musd != address(0), "StabilityPoolStrategy: zero musd");
        musd = IERC20(_musd);
        address sp = _stabilityPool;
        if (sp == address(0)) {
            require(
                block.chainid == MEZO_TESTNET_CHAIN_ID,
                "StabilityPoolStrategy: SP address required"
            );
            sp = MEZO_TESTNET_STABILITY_POOL;
        }
        stabilityPool = IStabilityPool(sp);
        vault = _vault;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "StabilityPoolStrategy: only vault");
        _;
    }

    /// @notice Point the strategy at a (new) vault. Owner-only.
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @inheritdoc IStrategy
    function deposit(uint256 amount) external onlyVault nonReentrant {
        musd.safeTransferFrom(msg.sender, address(this), amount);
        musd.safeIncreaseAllowance(address(stabilityPool), amount);
        stabilityPool.provideToSP(amount);
        _forwardToVault();
        emit DepositedToSP(amount);
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount) external onlyVault nonReentrant {
        uint256 before_ = musd.balanceOf(address(this));
        // Reverts at the pool level if there are under-collateralized troves
        // in the system (protocol constraint) or if we have no deposit.
        stabilityPool.withdrawFromSP(amount);
        uint256 received = musd.balanceOf(address(this)) - before_;
        _forwardToVault();
        emit WithdrawnFromSP(amount, received);
    }

    /// @inheritdoc IStrategy
    function totalAssets() external view returns (uint256) {
        return stabilityPool.getCompoundedMUSDDeposit(address(this));
    }

    /// @inheritdoc IStrategy
    function claimRewards() external onlyVault nonReentrant {
        if (
            stabilityPool.getCompoundedMUSDDeposit(address(this)) == 0
        ) return; // nothing staked -> no-op, avoids pool revert
        // withdrawFromSP(0): claims BTC collateral gains, leaves deposit.
        stabilityPool.withdrawFromSP(0);
        uint256 before_ = address(this).balance;
        _forwardToVault();
        emit RewardsClaimed(vault, before_ - address(this).balance);
    }

    /**
     * @notice View of pending native (BTC) collateral gains earned by this
     * strategy's Stability Pool deposit. Supported natively by the pool.
     */
    function claimableGains() external view returns (uint256) {
        return stabilityPool.getDepositorCollateralGain(address(this));
    }

    /// @notice Forward any MUSD / native balance held here to the vault.
    function _forwardToVault() internal {
        uint256 m = musd.balanceOf(address(this));
        if (m > 0) musd.safeTransfer(vault, m);
        uint256 n = address(this).balance;
        if (n > 0) {
            (bool ok, ) = vault.call{value: n}("");
            require(ok, "StabilityPoolStrategy: native forward failed");
        }
    }

    /// @notice Accept native BTC collateral gains sent by the Stability Pool.
    receive() external payable {}
}
