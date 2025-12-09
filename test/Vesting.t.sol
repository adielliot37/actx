// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ACTXToken} from "../src/ACTXToken.sol";
import {ACTXVesting} from "../src/Vesting.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ACTXVestingTest
 * @notice Comprehensive test suite for ACT.X Vesting contract
 */
contract ACTXVestingTest is Test {
    ACTXToken public token;
    ACTXVesting public vesting;

    address public treasury;
    address public reservoir;
    address public owner;

    address public teamMember1;
    address public teamMember2;
    address public advisor;

    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant VESTING_ALLOCATION = 20_000_000 * 10 ** 18;

    uint256 public constant DEFAULT_CLIFF = 365 days;
    uint256 public constant DEFAULT_DURATION = 4 * 365 days;

    uint256 public teamAmount1 = 1_000_000 * 10 ** 18;
    uint256 public teamAmount2 = 2_000_000 * 10 ** 18;
    uint256 public advisorAmount = 500_000 * 10 ** 18;

    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration
    );
    event TokensReleased(address indexed beneficiary, uint256 amount, uint256 timestamp);
    event VestingRevoked(address indexed beneficiary, uint256 unvestedAmount, uint256 timestamp);

    function setUp() public {
        // Setup addresses
        treasury = makeAddr("treasury");
        reservoir = makeAddr("reservoir");
        owner = makeAddr("owner");
        teamMember1 = makeAddr("teamMember1");
        teamMember2 = makeAddr("teamMember2");
        advisor = makeAddr("advisor");

        // Deploy token
        ACTXToken implementation = new ACTXToken();
        bytes memory initData =
            abi.encodeWithSelector(ACTXToken.initialize.selector, treasury, reservoir, 200, 10_000_000 * 10 ** 18);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = ACTXToken(address(proxy));

        // Deploy vesting contract
        vesting = new ACTXVesting(address(token), owner);

        // Fund vesting contract (treasury is tax exempt, so full amount transferred)
        vm.prank(treasury);
        token.transfer(address(vesting), VESTING_ALLOCATION);

        // Set vesting contract as tax exempt so beneficiaries receive full amounts
        vm.prank(treasury);
        token.setTaxExemption(address(vesting), true);
    }

    // ============ Vesting Schedule Creation Tests ============

    function test_CreateVestingSchedule_Success() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit VestingScheduleCreated(teamMember1, teamAmount1, startTime, DEFAULT_CLIFF, DEFAULT_DURATION);
        vesting.createVestingSchedule(teamMember1, teamAmount1, startTime);

        (
            uint256 totalAmount,
            uint256 releasedAmount,
            uint256 vestingStart,
            uint256 cliffDuration,
            uint256 vestingDuration,
            bool revoked
        ) = vesting.getVestingSchedule(teamMember1);

        assertEq(totalAmount, teamAmount1);
        assertEq(releasedAmount, 0);
        assertEq(vestingStart, startTime);
        assertEq(cliffDuration, DEFAULT_CLIFF);
        assertEq(vestingDuration, DEFAULT_DURATION);
        assertFalse(revoked);
    }

    function test_CreateVestingScheduleCustom_Success() public {
        uint256 startTime = block.timestamp;
        uint256 customCliff = 180 days;
        uint256 customDuration = 2 * 365 days;

        vm.prank(owner);
        vesting.createVestingScheduleCustom(advisor, advisorAmount, startTime, customCliff, customDuration);

        (,, uint256 vestingStart, uint256 cliffDuration, uint256 vestingDuration,) =
            vesting.getVestingSchedule(advisor);

        assertEq(vestingStart, startTime);
        assertEq(cliffDuration, customCliff);
        assertEq(vestingDuration, customDuration);
    }

    function test_CreateVestingSchedule_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ACTXVesting.ZeroAddress.selector);
        vesting.createVestingSchedule(address(0), teamAmount1, block.timestamp);
    }

    function test_CreateVestingSchedule_RevertZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(ACTXVesting.ZeroAmount.selector);
        vesting.createVestingSchedule(teamMember1, 0, block.timestamp);
    }

    function test_CreateVestingSchedule_RevertScheduleExists() public {
        vm.startPrank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        vm.expectRevert(ACTXVesting.ScheduleAlreadyExists.selector);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);
        vm.stopPrank();
    }

    function test_CreateVestingSchedule_RevertInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(ACTXVesting.InsufficientBalance.selector);
        vesting.createVestingSchedule(teamMember1, VESTING_ALLOCATION + 1, block.timestamp);
    }

    function test_BatchCreateVestingSchedules() public {
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = teamMember1;
        beneficiaries[1] = teamMember2;
        beneficiaries[2] = advisor;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = teamAmount1;
        amounts[1] = teamAmount2;
        amounts[2] = advisorAmount;

        uint256[] memory startTimes = new uint256[](3);
        startTimes[0] = block.timestamp;
        startTimes[1] = block.timestamp;
        startTimes[2] = block.timestamp + 30 days;

        vm.prank(owner);
        vesting.batchCreateVestingSchedules(beneficiaries, amounts, startTimes);

        assertEq(vesting.getBeneficiaryCount(), 3);
        assertEq(vesting.totalAllocated(), teamAmount1 + teamAmount2 + advisorAmount);
    }

    // ============ Token Release Tests ============

    function test_Release_BeforeCliff_ReturnsZero() public {
        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        // Warp to just before cliff
        vm.warp(block.timestamp + DEFAULT_CLIFF - 1);

        uint256 releasable = vesting.computeReleasableAmount(teamMember1);
        assertEq(releasable, 0);

        vm.prank(teamMember1);
        vm.expectRevert(ACTXVesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_Release_AtCliff_PartialVested() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, startTime);

        // Warp to exactly at cliff
        vm.warp(startTime + DEFAULT_CLIFF);

        uint256 releasable = vesting.computeReleasableAmount(teamMember1);
        // At cliff (25% of 4 years), 25% should be vested
        uint256 expectedVested = (teamAmount1 * DEFAULT_CLIFF) / DEFAULT_DURATION;
        assertEq(releasable, expectedVested);

        uint256 balanceBefore = token.balanceOf(teamMember1);

        vm.prank(teamMember1);
        vm.expectEmit(true, false, false, true);
        emit TokensReleased(teamMember1, expectedVested, block.timestamp);
        vesting.release();

        assertEq(token.balanceOf(teamMember1), balanceBefore + expectedVested);
    }

    function test_Release_AfterFullVesting() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, startTime);

        // Warp past full vesting
        vm.warp(startTime + DEFAULT_DURATION + 1);

        uint256 releasable = vesting.computeReleasableAmount(teamMember1);
        assertEq(releasable, teamAmount1);

        vm.prank(teamMember1);
        vesting.release();

        assertEq(token.balanceOf(teamMember1), teamAmount1);

        // No more to release
        assertEq(vesting.computeReleasableAmount(teamMember1), 0);
    }

    function test_Release_LinearVesting() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, startTime);

        // Test at 50% vesting (2 years)
        vm.warp(startTime + (DEFAULT_DURATION / 2));

        uint256 releasable = vesting.computeReleasableAmount(teamMember1);
        assertEq(releasable, teamAmount1 / 2);
    }

    function test_ReleaseFor_Success() public {
        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        vm.warp(block.timestamp + DEFAULT_CLIFF);

        uint256 expectedVested = (teamAmount1 * DEFAULT_CLIFF) / DEFAULT_DURATION;

        // Anyone can release for beneficiary
        vm.prank(teamMember2);
        vesting.releaseFor(teamMember1);

        assertEq(token.balanceOf(teamMember1), expectedVested);
    }

    function test_BatchRelease() public {
        vm.startPrank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);
        vesting.createVestingSchedule(teamMember2, teamAmount2, block.timestamp);
        vm.stopPrank();

        vm.warp(block.timestamp + DEFAULT_CLIFF);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = teamMember1;
        beneficiaries[1] = teamMember2;

        vesting.batchRelease(beneficiaries);

        uint256 expected1 = (teamAmount1 * DEFAULT_CLIFF) / DEFAULT_DURATION;
        uint256 expected2 = (teamAmount2 * DEFAULT_CLIFF) / DEFAULT_DURATION;

        assertEq(token.balanceOf(teamMember1), expected1);
        assertEq(token.balanceOf(teamMember2), expected2);
    }

    // ============ Revocation Tests ============

    function test_Revoke_Success() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, startTime);

        // Warp to 50% vesting
        vm.warp(startTime + (DEFAULT_DURATION / 2));

        uint256 vested = vesting.computeVestedAmount(teamMember1);
        uint256 unvested = teamAmount1 - vested;

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 memberBalanceBefore = token.balanceOf(teamMember1);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit VestingRevoked(teamMember1, unvested, block.timestamp);
        vesting.revoke(teamMember1);

        // Beneficiary receives vested tokens
        assertEq(token.balanceOf(teamMember1), memberBalanceBefore + vested);

        // Owner receives unvested tokens
        assertEq(token.balanceOf(owner), ownerBalanceBefore + unvested);

        // Schedule is revoked
        (,,,,, bool revoked) = vesting.getVestingSchedule(teamMember1);
        assertTrue(revoked);
    }

    function test_Revoke_BeforeCliff_AllUnvested() public {
        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, startTime);

        // Warp to before cliff
        vm.warp(startTime + DEFAULT_CLIFF - 1);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.revoke(teamMember1);

        // Nothing vested, so beneficiary gets nothing
        assertEq(token.balanceOf(teamMember1), 0);

        // Owner gets all back
        assertEq(token.balanceOf(owner), ownerBalanceBefore + teamAmount1);
    }

    function test_Revoke_RevertScheduleNotFound() public {
        vm.prank(owner);
        vm.expectRevert(ACTXVesting.ScheduleNotFound.selector);
        vesting.revoke(teamMember1);
    }

    function test_Revoke_RevertAlreadyRevoked() public {
        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        vm.warp(block.timestamp + DEFAULT_CLIFF);

        vm.startPrank(owner);
        vesting.revoke(teamMember1);

        vm.expectRevert(ACTXVesting.ScheduleRevoked.selector);
        vesting.revoke(teamMember1);
        vm.stopPrank();
    }

    // ============ Beneficiary Change Tests ============

    function test_ChangeBeneficiary_Success() public {
        address newBeneficiary = makeAddr("newBeneficiary");

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        vm.warp(block.timestamp + DEFAULT_CLIFF);

        vm.prank(owner);
        vesting.changeBeneficiary(teamMember1, newBeneficiary);

        // Old beneficiary revoked
        (,,,,, bool oldRevoked) = vesting.getVestingSchedule(teamMember1);
        assertTrue(oldRevoked);

        // New beneficiary has schedule
        (uint256 totalAmount,,,,, bool newRevoked) = vesting.getVestingSchedule(newBeneficiary);
        assertEq(totalAmount, teamAmount1);
        assertFalse(newRevoked);

        // New beneficiary can release
        vm.prank(newBeneficiary);
        vesting.release();

        uint256 expected = (teamAmount1 * DEFAULT_CLIFF) / DEFAULT_DURATION;
        assertEq(token.balanceOf(newBeneficiary), expected);
    }

    // ============ View Function Tests ============

    function test_GetTimeUntilCliff() public {
        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        uint256 timeUntilCliff = vesting.getTimeUntilCliff(teamMember1);
        assertEq(timeUntilCliff, DEFAULT_CLIFF);

        // Warp to after cliff
        vm.warp(block.timestamp + DEFAULT_CLIFF + 1);

        timeUntilCliff = vesting.getTimeUntilCliff(teamMember1);
        assertEq(timeUntilCliff, 0);
    }

    function test_GetTimeUntilFullyVested() public {
        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        uint256 timeUntilVested = vesting.getTimeUntilFullyVested(teamMember1);
        assertEq(timeUntilVested, DEFAULT_DURATION);

        // Warp past vesting
        vm.warp(block.timestamp + DEFAULT_DURATION + 1);

        timeUntilVested = vesting.getTimeUntilFullyVested(teamMember1);
        assertEq(timeUntilVested, 0);
    }

    function test_GetAllBeneficiaries() public {
        vm.startPrank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);
        vesting.createVestingSchedule(teamMember2, teamAmount2, block.timestamp);
        vm.stopPrank();

        address[] memory beneficiaries = vesting.getAllBeneficiaries();

        assertEq(beneficiaries.length, 2);
        assertEq(beneficiaries[0], teamMember1);
        assertEq(beneficiaries[1], teamMember2);
    }

    // ============ Admin Function Tests ============

    function test_SetVestingCreationPaused() public {
        vm.prank(owner);
        vesting.setVestingCreationPaused(true);

        vm.prank(owner);
        vm.expectRevert(ACTXVesting.VestingCreationIsPaused.selector);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);
    }

    // ============ Fuzz Tests ============

    function testFuzz_VestingCalculation(uint256 amount, uint256 timePassed) public {
        amount = bound(amount, 1e18, VESTING_ALLOCATION);
        timePassed = bound(timePassed, 0, DEFAULT_DURATION * 2);

        uint256 startTime = block.timestamp;

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, amount, startTime);

        vm.warp(startTime + timePassed);

        uint256 vested = vesting.computeVestedAmount(teamMember1);

        if (timePassed < DEFAULT_CLIFF) {
            assertEq(vested, 0);
        } else if (timePassed >= DEFAULT_DURATION) {
            assertEq(vested, amount);
        } else {
            uint256 expectedVested = (amount * timePassed) / DEFAULT_DURATION;
            assertEq(vested, expectedVested);
        }
    }

    function testFuzz_MultipleReleases(uint256 releaseCount) public {
        releaseCount = bound(releaseCount, 1, 10);

        vm.prank(owner);
        vesting.createVestingSchedule(teamMember1, teamAmount1, block.timestamp);

        uint256 totalReleased;
        uint256 vestingPeriodChunk = DEFAULT_DURATION / releaseCount;

        for (uint256 i = 0; i < releaseCount; i++) {
            vm.warp(block.timestamp + vestingPeriodChunk);

            uint256 releasable = vesting.computeReleasableAmount(teamMember1);
            if (releasable > 0) {
                vm.prank(teamMember1);
                vesting.release();
                totalReleased += releasable;
            }
        }

        // Total released should be approximately the total amount
        // Allow for rounding errors due to integer division in vesting calculation
        assertLe(totalReleased, teamAmount1);
        // Account for rounding errors (max 1 wei per release + potential remainder)
        assertGe(totalReleased, (teamAmount1 * 99) / 100); // At least 99% should be released
    }
}

