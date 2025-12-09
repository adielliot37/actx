// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title ACTXToken
/// @notice ERC-20 rewards token with UUPS upgradeability, role-based access, and transaction tax
contract ACTXToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant MAX_TAX_RATE_BP = 1000;
    uint256 public constant BASIS_POINTS = 10_000;

    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant TAX_MANAGER_ROLE = keccak256("TAX_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 private _taxRateBasisPoints;
    address private _reservoirAddress;
    address private _treasuryAddress;
    uint256 private _rewardPoolBalance;
    mapping(address => bool) private _taxExempt;
    uint256 private _totalRewardsDistributed;
    uint256 private _version;

    event RewardDistributed(address indexed recipient, uint256 amount, uint256 rewardPoolRemaining, uint256 timestamp);
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event ReservoirAddressUpdated(address indexed oldReservoir, address indexed newReservoir);
    event TaxExemptionUpdated(address indexed account, bool exempt);
    event RewardPoolFunded(address indexed funder, uint256 amount, uint256 newBalance);
    event TaxCollected(address indexed from, address indexed to, uint256 taxAmount, uint256 netAmount);
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event LeaderboardAction(address indexed user, string action, uint256 amount, bytes metadata);

    error ZeroAddress();
    error ZeroAmount();
    error TaxRateTooHigh(uint256 provided, uint256 maximum);
    error InsufficientRewardPool(uint256 requested, uint256 available);
    error TransferAmountTooLow();
    error UnauthorizedCaller(address caller, bytes32 requiredRole);

    modifier notZeroAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier notZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address treasury,
        address reservoir,
        uint256 initialTaxRateBP,
        uint256 rewardPoolAllocation
    ) external initializer notZeroAddress(treasury) notZeroAddress(reservoir) {
        if (initialTaxRateBP > MAX_TAX_RATE_BP) {
            revert TaxRateTooHigh(initialTaxRateBP, MAX_TAX_RATE_BP);
        }

        __ERC20_init("ACT.X Token", "ACTX");
        __ERC20Burnable_init();
        __ERC20Permit_init("ACT.X Token");
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, treasury);
        _grantRole(REWARD_MANAGER_ROLE, treasury);
        _grantRole(PAUSER_ROLE, treasury);
        _grantRole(TAX_MANAGER_ROLE, treasury);
        _grantRole(UPGRADER_ROLE, treasury);

        _treasuryAddress = treasury;
        _reservoirAddress = reservoir;
        _taxRateBasisPoints = initialTaxRateBP;
        _version = 1;

        _taxExempt[treasury] = true;
        _taxExempt[reservoir] = true;
        _taxExempt[address(this)] = true;

        _mint(treasury, TOTAL_SUPPLY);

        if (rewardPoolAllocation > 0) {
            if (rewardPoolAllocation > TOTAL_SUPPLY) {
                revert InsufficientRewardPool(rewardPoolAllocation, TOTAL_SUPPLY);
            }
            _rewardPoolBalance = rewardPoolAllocation;
            emit RewardPoolFunded(treasury, rewardPoolAllocation, rewardPoolAllocation);
        }
    }

    function distributeReward(
        address recipient,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(REWARD_MANAGER_ROLE) notZeroAddress(recipient) notZeroAmount(amount) {
        if (amount > _rewardPoolBalance) {
            revert InsufficientRewardPool(amount, _rewardPoolBalance);
        }

        _rewardPoolBalance -= amount;
        _totalRewardsDistributed += amount;
        _transfer(_treasuryAddress, recipient, amount);

        emit RewardDistributed(recipient, amount, _rewardPoolBalance, block.timestamp);
        emit LeaderboardAction(recipient, "REWARD", amount, abi.encode(block.timestamp, _totalRewardsDistributed));
    }

    function batchDistributeRewards(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused onlyRole(REWARD_MANAGER_ROLE) {
        require(recipients.length == amounts.length, "ACTXToken: arrays length mismatch");
        require(recipients.length > 0, "ACTXToken: empty arrays");

        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked { ++i; }
        }

        if (totalAmount > _rewardPoolBalance) {
            revert InsufficientRewardPool(totalAmount, _rewardPoolBalance);
        }

        _rewardPoolBalance -= totalAmount;
        _totalRewardsDistributed += totalAmount;

        for (uint256 i = 0; i < recipients.length;) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();

            _transfer(_treasuryAddress, recipients[i], amounts[i]);
            emit RewardDistributed(recipients[i], amounts[i], _rewardPoolBalance, block.timestamp);
            unchecked { ++i; }
        }
    }

    function fundRewardPool(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) notZeroAmount(amount) {
        require(balanceOf(_treasuryAddress) >= amount + _rewardPoolBalance, "ACTXToken: insufficient treasury balance");
        _rewardPoolBalance += amount;
        emit RewardPoolFunded(msg.sender, amount, _rewardPoolBalance);
    }

    function setTaxRate(uint256 newTaxRateBP) external onlyRole(TAX_MANAGER_ROLE) {
        if (newTaxRateBP > MAX_TAX_RATE_BP) {
            revert TaxRateTooHigh(newTaxRateBP, MAX_TAX_RATE_BP);
        }
        uint256 oldRate = _taxRateBasisPoints;
        _taxRateBasisPoints = newTaxRateBP;
        emit TaxRateUpdated(oldRate, newTaxRateBP);
    }

    function setReservoirAddress(address newReservoir) external onlyRole(TAX_MANAGER_ROLE) notZeroAddress(newReservoir) {
        address oldReservoir = _reservoirAddress;
        _reservoirAddress = newReservoir;
        _taxExempt[newReservoir] = true;
        emit ReservoirAddressUpdated(oldReservoir, newReservoir);
        emit TaxExemptionUpdated(newReservoir, true);
    }

    function setTaxExemption(address account, bool exempt) external onlyRole(TAX_MANAGER_ROLE) notZeroAddress(account) {
        _taxExempt[account] = exempt;
        emit TaxExemptionUpdated(account, exempt);
    }

    function calculateTax(uint256 amount) public view returns (uint256 taxAmount, uint256 netAmount) {
        if (_taxRateBasisPoints == 0) {
            return (0, amount);
        }
        taxAmount = (amount * _taxRateBasisPoints) / BASIS_POINTS;
        netAmount = amount - taxAmount;
    }

    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        if (from == address(0) || to == address(0) || _taxExempt[from] || _taxExempt[to]) {
            super._update(from, to, value);
            return;
        }

        if (_taxRateBasisPoints > 0 && _reservoirAddress != address(0)) {
            (uint256 taxAmount, uint256 netAmount) = calculateTax(value);
            if (netAmount == 0) revert TransferAmountTooLow();

            if (taxAmount > 0) {
                super._update(from, _reservoirAddress, taxAmount);
            }
            super._update(from, to, netAmount);

            emit TaxCollected(from, to, taxAmount, netAmount);
            emit LeaderboardAction(from, "TRANSFER", value, abi.encode(to, taxAmount, netAmount));
        } else {
            super._update(from, to, value);
            emit LeaderboardAction(from, "TRANSFER", value, abi.encode(to, 0, value));
        }
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) notZeroAddress(newImplementation) {
        _version++;
        emit ContractUpgraded(newImplementation, _version);
    }

    function rewardPoolBalance() external view returns (uint256) { return _rewardPoolBalance; }
    function totalRewardsDistributed() external view returns (uint256) { return _totalRewardsDistributed; }
    function taxRateBasisPoints() external view returns (uint256) { return _taxRateBasisPoints; }
    function reservoirAddress() external view returns (address) { return _reservoirAddress; }
    function treasuryAddress() external view returns (address) { return _treasuryAddress; }
    function isTaxExempt(address account) external view returns (bool) { return _taxExempt[account]; }
    function version() external view returns (uint256) { return _version; }
    function isRewardManager(address account) external view returns (bool) { return hasRole(REWARD_MANAGER_ROLE, account); }

    function getTokenStats() external view returns (
        uint256 totalSupply_,
        uint256 treasuryBalance_,
        uint256 rewardPool_,
        uint256 totalDistributed_,
        uint256 currentTaxRate_,
        uint256 contractVersion_
    ) {
        return (totalSupply(), balanceOf(_treasuryAddress), _rewardPoolBalance, _totalRewardsDistributed, _taxRateBasisPoints, _version);
    }
}
