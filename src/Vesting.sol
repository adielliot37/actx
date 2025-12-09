// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ACTXVesting
/// @notice Linear vesting contract with cliff period for team and advisors
contract ACTXVesting is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        bool revoked;
        bool initialized;
    }

    uint256 public constant DEFAULT_CLIFF_DURATION = 365 days;
    uint256 public constant DEFAULT_VESTING_DURATION = 4 * 365 days;

    IERC20 public immutable actxToken;
    mapping(address => VestingSchedule) public vestingSchedules;
    address[] public beneficiaries;
    uint256 public totalAllocated;
    uint256 public totalReleased;
    bool public vestingCreationPaused;

    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    );
    event TokensReleased(address indexed beneficiary, uint256 amount, uint256 timestamp);
    event VestingRevoked(address indexed beneficiary, uint256 unvestedAmount, uint256 timestamp);
    event VestingCreationPaused(bool paused);
    event BeneficiaryChanged(address indexed oldBeneficiary, address indexed newBeneficiary);

    error ZeroAddress();
    error ZeroAmount();
    error ScheduleAlreadyExists();
    error ScheduleNotFound();
    error ScheduleRevoked();
    error NothingToRelease();
    error InsufficientBalance();
    error VestingCreationIsPaused();
    error CliffNotReached();
    error InvalidDuration();

    constructor(address _actxToken, address _owner) Ownable(_owner) {
        if (_actxToken == address(0)) revert ZeroAddress();
        actxToken = IERC20(_actxToken);
    }

    function createVestingSchedule(address beneficiary, uint256 totalAmount, uint256 startTime) external onlyOwner {
        _createVestingSchedule(beneficiary, totalAmount, startTime, DEFAULT_CLIFF_DURATION, DEFAULT_VESTING_DURATION);
    }

    function createVestingScheduleCustom(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) external onlyOwner {
        _createVestingSchedule(beneficiary, totalAmount, startTime, cliffDuration, vestingDuration);
    }

    function _createVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) internal {
        if (vestingCreationPaused) revert VestingCreationIsPaused();
        if (beneficiary == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert ZeroAmount();
        if (vestingSchedules[beneficiary].initialized) revert ScheduleAlreadyExists();
        if (vestingDuration == 0 || cliffDuration > vestingDuration) revert InvalidDuration();

        uint256 currentBalance = actxToken.balanceOf(address(this));
        if (currentBalance < totalAllocated + totalAmount - totalReleased) {
            revert InsufficientBalance();
        }

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: totalAmount,
            releasedAmount: 0,
            startTime: startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            revoked: false,
            initialized: true
        });

        beneficiaries.push(beneficiary);
        totalAllocated += totalAmount;
        emit VestingScheduleCreated(beneficiary, totalAmount, startTime, cliffDuration, vestingDuration);
    }

    function batchCreateVestingSchedules(
        address[] calldata _beneficiaries,
        uint256[] calldata _amounts,
        uint256[] calldata _startTimes
    ) external onlyOwner {
        require(
            _beneficiaries.length == _amounts.length && _amounts.length == _startTimes.length,
            "ACTXVesting: arrays length mismatch"
        );
        for (uint256 i = 0; i < _beneficiaries.length;) {
            _createVestingSchedule(
                _beneficiaries[i], _amounts[i], _startTimes[i], DEFAULT_CLIFF_DURATION, DEFAULT_VESTING_DURATION
            );
            unchecked {
                ++i;
            }
        }
    }

    function release() external nonReentrant returns (uint256 amount) {
        return _release(msg.sender);
    }

    function releaseFor(address beneficiary) external nonReentrant returns (uint256 amount) {
        return _release(beneficiary);
    }

    function _release(address beneficiary) internal returns (uint256 amount) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) revert ScheduleNotFound();
        if (schedule.revoked) revert ScheduleRevoked();

        amount = _computeReleasableAmount(schedule);
        if (amount == 0) revert NothingToRelease();

        schedule.releasedAmount += amount;
        totalReleased += amount;
        actxToken.safeTransfer(beneficiary, amount);

        emit TokensReleased(beneficiary, amount, block.timestamp);
    }

    function batchRelease(address[] calldata _beneficiaries) external nonReentrant {
        for (uint256 i = 0; i < _beneficiaries.length;) {
            VestingSchedule storage schedule = vestingSchedules[_beneficiaries[i]];
            if (schedule.initialized && !schedule.revoked) {
                uint256 amount = _computeReleasableAmount(schedule);
                if (amount > 0) {
                    schedule.releasedAmount += amount;
                    totalReleased += amount;
                    actxToken.safeTransfer(_beneficiaries[i], amount);
                    emit TokensReleased(_beneficiaries[i], amount, block.timestamp);
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function revoke(address beneficiary) external onlyOwner nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) revert ScheduleNotFound();
        if (schedule.revoked) revert ScheduleRevoked();

        uint256 vestedAmount = _computeVestedAmount(schedule);
        uint256 releasableAmount = vestedAmount - schedule.releasedAmount;

        if (releasableAmount > 0) {
            schedule.releasedAmount += releasableAmount;
            totalReleased += releasableAmount;
            actxToken.safeTransfer(beneficiary, releasableAmount);
            emit TokensReleased(beneficiary, releasableAmount, block.timestamp);
        }

        uint256 unvestedAmount = schedule.totalAmount - vestedAmount;
        schedule.revoked = true;
        totalAllocated -= unvestedAmount;

        if (unvestedAmount > 0) {
            actxToken.safeTransfer(owner(), unvestedAmount);
        }

        emit VestingRevoked(beneficiary, unvestedAmount, block.timestamp);
    }

    function changeBeneficiary(address oldBeneficiary, address newBeneficiary) external onlyOwner {
        if (newBeneficiary == address(0)) revert ZeroAddress();

        VestingSchedule storage oldSchedule = vestingSchedules[oldBeneficiary];
        if (!oldSchedule.initialized) revert ScheduleNotFound();
        if (oldSchedule.revoked) revert ScheduleRevoked();
        if (vestingSchedules[newBeneficiary].initialized) revert ScheduleAlreadyExists();

        vestingSchedules[newBeneficiary] = oldSchedule;
        oldSchedule.revoked = true;

        for (uint256 i = 0; i < beneficiaries.length;) {
            if (beneficiaries[i] == oldBeneficiary) {
                beneficiaries[i] = newBeneficiary;
                break;
            }
            unchecked {
                ++i;
            }
        }

        emit BeneficiaryChanged(oldBeneficiary, newBeneficiary);
    }

    function getVestingSchedule(address beneficiary)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 releasedAmount,
            uint256 startTime,
            uint256 cliffDuration,
            uint256 vestingDuration,
            bool revoked
        )
    {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        return (
            schedule.totalAmount,
            schedule.releasedAmount,
            schedule.startTime,
            schedule.cliffDuration,
            schedule.vestingDuration,
            schedule.revoked
        );
    }

    function computeReleasableAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized || schedule.revoked) return 0;
        return _computeReleasableAmount(schedule);
    }

    function computeVestedAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) return 0;
        return _computeVestedAmount(schedule);
    }

    function _computeReleasableAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        return _computeVestedAmount(schedule) - schedule.releasedAmount;
    }

    function _computeVestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;
        if (currentTime < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }
        if (currentTime >= schedule.startTime + schedule.vestingDuration) {
            return schedule.totalAmount;
        }
        uint256 timeFromStart = currentTime - schedule.startTime;
        return (schedule.totalAmount * timeFromStart) / schedule.vestingDuration;
    }

    function getBeneficiaryCount() external view returns (uint256) {
        return beneficiaries.length;
    }

    function getAllBeneficiaries() external view returns (address[] memory) {
        return beneficiaries;
    }

    function getTimeUntilCliff(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) return 0;
        uint256 cliffEnd = schedule.startTime + schedule.cliffDuration;
        if (block.timestamp >= cliffEnd) return 0;
        return cliffEnd - block.timestamp;
    }

    function getTimeUntilFullyVested(address beneficiary) external view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        if (!schedule.initialized) return 0;
        uint256 vestingEnd = schedule.startTime + schedule.vestingDuration;
        if (block.timestamp >= vestingEnd) return 0;
        return vestingEnd - block.timestamp;
    }

    function setVestingCreationPaused(bool paused) external onlyOwner {
        vestingCreationPaused = paused;
        emit VestingCreationPaused(paused);
    }

    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        if (token == address(actxToken)) {
            uint256 currentBalance = actxToken.balanceOf(address(this));
            uint256 committed = totalAllocated - totalReleased;
            require(amount <= currentBalance - committed, "ACTXVesting: cannot recover committed tokens");
        }
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}
