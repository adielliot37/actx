// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ACTXToken} from "../src/ACTXToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/**
 * @title ACTXTokenTest
 * @notice Comprehensive test suite for ACT.X Token
 * @dev Includes unit tests, fuzz tests, and edge case testing
 */
contract ACTXTokenTest is Test {
    ACTXToken public token;
    ACTXToken public implementation;
    ERC1967Proxy public proxy;

    address public treasury;
    address public reservoir;
    address public rewardManager;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant INITIAL_TAX_RATE = 200; // 2%
    uint256 public constant REWARD_POOL_ALLOCATION = 10_000_000 * 10 ** 18; // 10M tokens
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;

    // Events to test
    event RewardDistributed(
        address indexed recipient, uint256 amount, uint256 rewardPoolRemaining, uint256 timestamp
    );
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event ReservoirAddressUpdated(address indexed oldReservoir, address indexed newReservoir);
    event TaxCollected(address indexed from, address indexed to, uint256 taxAmount, uint256 netAmount);

    function setUp() public {
        // Setup addresses
        treasury = makeAddr("treasury");
        reservoir = makeAddr("reservoir");
        rewardManager = makeAddr("rewardManager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy implementation
        implementation = new ACTXToken();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector, treasury, reservoir, INITIAL_TAX_RATE, REWARD_POOL_ALLOCATION
        );

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Get token interface
        token = ACTXToken(address(proxy));

        // Grant reward manager role (treasury already has this role by default)
        // Note: Cache the role first since vm.prank only applies to the next external call
        bytes32 rewardManagerRole = token.REWARD_MANAGER_ROLE();
        vm.prank(treasury);
        token.grantRole(rewardManagerRole, rewardManager);
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public view {
        assertEq(token.name(), "ACT.X Token");
        assertEq(token.symbol(), "ACTX");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(treasury), TOTAL_SUPPLY);
        assertEq(token.taxRateBasisPoints(), INITIAL_TAX_RATE);
        assertEq(token.reservoirAddress(), reservoir);
        assertEq(token.treasuryAddress(), treasury);
        assertEq(token.rewardPoolBalance(), REWARD_POOL_ALLOCATION);
        assertEq(token.version(), 1);
    }

    function test_Initialize_RolesAssigned() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), treasury));
        assertTrue(token.hasRole(token.REWARD_MANAGER_ROLE(), treasury));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), treasury));
        assertTrue(token.hasRole(token.TAX_MANAGER_ROLE(), treasury));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), treasury));
    }

    function test_Initialize_TaxExemptions() public view {
        assertTrue(token.isTaxExempt(treasury));
        assertTrue(token.isTaxExempt(reservoir));
        assertTrue(token.isTaxExempt(address(token)));
    }

    function test_Initialize_RevertOnReinitialize() public {
        vm.expectRevert();
        token.initialize(treasury, reservoir, INITIAL_TAX_RATE, REWARD_POOL_ALLOCATION);
    }

    function test_Initialize_RevertOnZeroTreasury() public {
        ACTXToken newImpl = new ACTXToken();
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector, address(0), reservoir, INITIAL_TAX_RATE, REWARD_POOL_ALLOCATION
        );
        vm.expectRevert(ACTXToken.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_Initialize_RevertOnZeroReservoir() public {
        ACTXToken newImpl = new ACTXToken();
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector, treasury, address(0), INITIAL_TAX_RATE, REWARD_POOL_ALLOCATION
        );
        vm.expectRevert(ACTXToken.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_Initialize_RevertOnTaxRateTooHigh() public {
        ACTXToken newImpl = new ACTXToken();
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector, treasury, reservoir, 1001, REWARD_POOL_ALLOCATION // 10.01% exceeds max
        );
        vm.expectRevert(abi.encodeWithSelector(ACTXToken.TaxRateTooHigh.selector, 1001, 1000));
        new ERC1967Proxy(address(newImpl), initData);
    }

    // ============ Reward Distribution Tests ============

    function test_DistributeReward_Success() public {
        uint256 rewardAmount = 1000 * 10 ** 18;

        vm.prank(rewardManager);
        vm.expectEmit(true, false, false, true);
        emit RewardDistributed(user1, rewardAmount, REWARD_POOL_ALLOCATION - rewardAmount, block.timestamp);
        token.distributeReward(user1, rewardAmount);

        assertEq(token.balanceOf(user1), rewardAmount);
        assertEq(token.rewardPoolBalance(), REWARD_POOL_ALLOCATION - rewardAmount);
        assertEq(token.totalRewardsDistributed(), rewardAmount);
    }

    function test_DistributeReward_RevertNotRewardManager() public {
        vm.prank(user1);
        vm.expectRevert();
        token.distributeReward(user1, 1000);
    }

    function test_DistributeReward_RevertZeroAddress() public {
        vm.prank(rewardManager);
        vm.expectRevert(ACTXToken.ZeroAddress.selector);
        token.distributeReward(address(0), 1000);
    }

    function test_DistributeReward_RevertZeroAmount() public {
        vm.prank(rewardManager);
        vm.expectRevert(ACTXToken.ZeroAmount.selector);
        token.distributeReward(user1, 0);
    }

    function test_DistributeReward_RevertInsufficientPool() public {
        uint256 excessAmount = REWARD_POOL_ALLOCATION + 1;

        vm.prank(rewardManager);
        vm.expectRevert(abi.encodeWithSelector(ACTXToken.InsufficientRewardPool.selector, excessAmount, REWARD_POOL_ALLOCATION));
        token.distributeReward(user1, excessAmount);
    }

    function test_BatchDistributeRewards_Success() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 * 10 ** 18;
        amounts[1] = 200 * 10 ** 18;
        amounts[2] = 300 * 10 ** 18;

        vm.prank(rewardManager);
        token.batchDistributeRewards(recipients, amounts);

        assertEq(token.balanceOf(user1), 100 * 10 ** 18);
        assertEq(token.balanceOf(user2), 200 * 10 ** 18);
        assertEq(token.balanceOf(user3), 300 * 10 ** 18);
        assertEq(token.totalRewardsDistributed(), 600 * 10 ** 18);
    }

    // ============ Transaction Tax Tests ============

    function test_Transfer_WithTax() public {
        // First distribute some tokens to user1
        uint256 initialAmount = 1000 * 10 ** 18;
        vm.prank(rewardManager);
        token.distributeReward(user1, initialAmount);

        // Transfer from user1 to user2 (both non-exempt)
        uint256 transferAmount = 100 * 10 ** 18;
        (uint256 expectedTax, uint256 expectedNet) = token.calculateTax(transferAmount);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit TaxCollected(user1, user2, expectedTax, expectedNet);
        token.transfer(user2, transferAmount);

        assertEq(token.balanceOf(user2), expectedNet);
        assertEq(token.balanceOf(reservoir), expectedTax);
    }

    function test_Transfer_NoTaxForExempt() public {
        // Treasury is tax exempt
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.prank(treasury);
        token.transfer(user1, transferAmount);

        // User1 receives full amount (treasury is exempt)
        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(reservoir), 0);
    }

    function test_CalculateTax_Accuracy() public view {
        uint256 amount = 1000 * 10 ** 18;
        (uint256 taxAmount, uint256 netAmount) = token.calculateTax(amount);

        // 2% of 1000 = 20
        assertEq(taxAmount, 20 * 10 ** 18);
        assertEq(netAmount, 980 * 10 ** 18);
        assertEq(taxAmount + netAmount, amount);
    }

    function test_SetTaxRate_Success() public {
        uint256 newRate = 500; // 5%

        vm.prank(treasury);
        vm.expectEmit(false, false, false, true);
        emit TaxRateUpdated(INITIAL_TAX_RATE, newRate);
        token.setTaxRate(newRate);

        assertEq(token.taxRateBasisPoints(), newRate);
    }

    function test_SetTaxRate_RevertTooHigh() public {
        vm.prank(treasury);
        vm.expectRevert(abi.encodeWithSelector(ACTXToken.TaxRateTooHigh.selector, 1001, 1000));
        token.setTaxRate(1001);
    }

    function test_SetTaxRate_ZeroDisablesTax() public {
        vm.prank(treasury);
        token.setTaxRate(0);

        // Distribute tokens
        vm.prank(rewardManager);
        token.distributeReward(user1, 1000 * 10 ** 18);

        // Transfer should have no tax
        vm.prank(user1);
        token.transfer(user2, 100 * 10 ** 18);

        assertEq(token.balanceOf(user2), 100 * 10 ** 18);
        assertEq(token.balanceOf(reservoir), 0);
    }

    function test_SetReservoirAddress_Success() public {
        address newReservoir = makeAddr("newReservoir");

        vm.prank(treasury);
        vm.expectEmit(true, true, false, false);
        emit ReservoirAddressUpdated(reservoir, newReservoir);
        token.setReservoirAddress(newReservoir);

        assertEq(token.reservoirAddress(), newReservoir);
        assertTrue(token.isTaxExempt(newReservoir));
    }

    function test_SetTaxExemption_Success() public {
        assertFalse(token.isTaxExempt(user1));

        vm.prank(treasury);
        token.setTaxExemption(user1, true);

        assertTrue(token.isTaxExempt(user1));
    }

    // ============ Reward Pool Management Tests ============

    function test_FundRewardPool_Success() public {
        uint256 additionalFunding = 5_000_000 * 10 ** 18;

        vm.prank(treasury);
        token.fundRewardPool(additionalFunding);

        assertEq(token.rewardPoolBalance(), REWARD_POOL_ALLOCATION + additionalFunding);
    }

    function test_FundRewardPool_RevertInsufficientTreasury() public {
        // Try to fund more than treasury has available
        uint256 excessFunding = TOTAL_SUPPLY;

        vm.prank(treasury);
        vm.expectRevert("ACTXToken: insufficient treasury balance");
        token.fundRewardPool(excessFunding);
    }

    // ============ Pause Tests ============

    function test_Pause_Success() public {
        vm.prank(treasury);
        token.pause();

        assertTrue(token.paused());
    }

    function test_Transfer_RevertWhenPaused() public {
        vm.prank(treasury);
        token.pause();

        vm.prank(treasury);
        vm.expectRevert();
        token.transfer(user1, 1000);
    }

    function test_DistributeReward_RevertWhenPaused() public {
        vm.prank(treasury);
        token.pause();

        vm.prank(rewardManager);
        vm.expectRevert();
        token.distributeReward(user1, 1000);
    }

    function test_Unpause_Success() public {
        vm.prank(treasury);
        token.pause();

        vm.prank(treasury);
        token.unpause();

        assertFalse(token.paused());
    }

    // ============ View Function Tests ============

    function test_GetTokenStats() public view {
        (
            uint256 totalSupply_,
            uint256 treasuryBalance_,
            uint256 rewardPool_,
            uint256 totalDistributed_,
            uint256 currentTaxRate_,
            uint256 contractVersion_
        ) = token.getTokenStats();

        assertEq(totalSupply_, TOTAL_SUPPLY);
        assertEq(treasuryBalance_, TOTAL_SUPPLY);
        assertEq(rewardPool_, REWARD_POOL_ALLOCATION);
        assertEq(totalDistributed_, 0);
        assertEq(currentTaxRate_, INITIAL_TAX_RATE);
        assertEq(contractVersion_, 1);
    }

    function test_IsRewardManager() public view {
        assertTrue(token.isRewardManager(rewardManager));
        assertTrue(token.isRewardManager(treasury));
        assertFalse(token.isRewardManager(user1));
    }

    // ============ ERC20 Compliance Tests ============

    function test_Approve_Success() public {
        vm.prank(treasury);
        token.approve(user1, 1000 * 10 ** 18);

        assertEq(token.allowance(treasury, user1), 1000 * 10 ** 18);
    }

    function test_TransferFrom_Success() public {
        // Treasury approves user1
        vm.prank(treasury);
        token.approve(user1, 1000 * 10 ** 18);

        // User1 transfers from treasury to user2
        vm.prank(user1);
        token.transferFrom(treasury, user2, 500 * 10 ** 18);

        // Treasury is exempt, so no tax
        assertEq(token.balanceOf(user2), 500 * 10 ** 18);
    }

    function test_Burn_Success() public {
        // Distribute tokens first
        vm.prank(rewardManager);
        token.distributeReward(user1, 1000 * 10 ** 18);

        uint256 burnAmount = 100 * 10 ** 18;
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user1), balanceBefore - burnAmount);
        assertEq(token.totalSupply(), TOTAL_SUPPLY - burnAmount);
    }

    // ============ Fuzz Tests ============

    function testFuzz_DistributeReward(uint256 amount) public {
        amount = bound(amount, 1, REWARD_POOL_ALLOCATION);

        vm.prank(rewardManager);
        token.distributeReward(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.rewardPoolBalance(), REWARD_POOL_ALLOCATION - amount);
    }

    function testFuzz_CalculateTax(uint256 amount, uint256 taxRate) public {
        // Bound amount to prevent overflow in multiplication
        amount = bound(amount, 0, type(uint256).max / 10_000);
        taxRate = bound(taxRate, 0, 1000);

        vm.prank(treasury);
        token.setTaxRate(taxRate);

        (uint256 taxAmount, uint256 netAmount) = token.calculateTax(amount);

        assertEq(taxAmount + netAmount, amount);
        if (taxRate > 0) {
            assertEq(taxAmount, (amount * taxRate) / 10_000);
        } else {
            assertEq(taxAmount, 0);
        }
    }

    function testFuzz_Transfer_TaxDeduction(uint256 transferAmount) public {
        // Bound to reasonable amounts
        transferAmount = bound(transferAmount, 1000, 10_000_000 * 10 ** 18);

        // Distribute to user1
        vm.prank(rewardManager);
        token.distributeReward(user1, transferAmount);

        // Calculate expected values
        (uint256 expectedTax, uint256 expectedNet) = token.calculateTax(transferAmount);

        // Transfer
        vm.prank(user1);
        token.transfer(user2, transferAmount);

        // Verify
        assertEq(token.balanceOf(user2), expectedNet);
        assertEq(token.balanceOf(reservoir), expectedTax);
    }

    function testFuzz_SetTaxRate_ValidRange(uint256 newRate) public {
        newRate = bound(newRate, 0, 1000);

        vm.prank(treasury);
        token.setTaxRate(newRate);

        assertEq(token.taxRateBasisPoints(), newRate);
    }

    function testFuzz_SetTaxRate_InvalidRange(uint256 newRate) public {
        newRate = bound(newRate, 1001, type(uint256).max);

        vm.prank(treasury);
        vm.expectRevert(abi.encodeWithSelector(ACTXToken.TaxRateTooHigh.selector, newRate, 1000));
        token.setTaxRate(newRate);
    }

    // ============ Edge Case Tests ============

    function test_Transfer_MinimumAmount() public {
        // Distribute a small amount to user1
        uint256 smallAmount = 100 * 10 ** 18;
        vm.prank(rewardManager);
        token.distributeReward(user1, smallAmount);

        // Set a high tax rate (10%) to test minimum amount scenario
        vm.prank(treasury);
        token.setTaxRate(1000); // 10%

        // Transfer amount so small that after 10% tax, net amount would be 0
        // For 10% tax: tax = amount * 1000 / 10000, net = amount - tax
        // If amount = 9, tax = 0, net = 9 (no tax due to rounding)
        // For net to be 0, we need amount where 10% rounds up to amount
        // Actually with integer division, we need to be more careful
        
        // With current implementation, net = 0 only if amount <= tax
        // For 10% tax: amount * 9000 / 10000 = 0 only when amount < 10000/9000 ≈ 1.11
        // So amount of 1 should result in net = 0
        
        // The contract checks if netAmount == 0, not taxAmount
        // With tax 10% and amount 1: tax = 1 * 1000 / 10000 = 0, net = 1
        // So we need to test with a scenario where net becomes 0
        
        // Actually with basis points calculation:
        // taxAmount = (1 * 1000) / 10000 = 0 (integer division)
        // netAmount = 1 - 0 = 1
        // So it won't revert for amount 1 with 10% tax
        
        // Let's test that small transfers work correctly instead
        vm.prank(user1);
        token.transfer(user2, 1); // This should work, user2 gets 1 wei
        
        assertEq(token.balanceOf(user2), 1);
    }

    function test_Transfer_LargeAmount() public {
        // Distribute large amount
        uint256 largeAmount = 50_000_000 * 10 ** 18;
        vm.prank(treasury);
        token.fundRewardPool(largeAmount);

        vm.prank(rewardManager);
        token.distributeReward(user1, largeAmount);

        // Transfer
        (uint256 expectedTax, uint256 expectedNet) = token.calculateTax(largeAmount);

        vm.prank(user1);
        token.transfer(user2, largeAmount);

        assertEq(token.balanceOf(user2), expectedNet);
        assertEq(token.balanceOf(reservoir), expectedTax);
    }

    function test_MultipleTransfers_TaxAccumulation() public {
        // Distribute tokens
        vm.prank(rewardManager);
        token.distributeReward(user1, 10_000 * 10 ** 18);

        // Multiple transfers
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user1);
            token.transfer(user2, 1000 * 10 ** 18);
        }

        // Calculate expected reservoir balance
        uint256 totalTransferred = 5000 * 10 ** 18;
        (uint256 expectedTax,) = token.calculateTax(1000 * 10 ** 18);
        uint256 totalExpectedTax = expectedTax * 5;

        assertEq(token.balanceOf(reservoir), totalExpectedTax);
    }
}

/**
 * @title ACTXTokenUpgradeTest
 * @notice Tests for UUPS upgrade functionality
 */
contract ACTXTokenUpgradeTest is Test {
    ACTXToken public token;
    ACTXToken public implementation;
    ERC1967Proxy public proxy;

    address public treasury;
    address public reservoir;

    function setUp() public {
        treasury = makeAddr("treasury");
        reservoir = makeAddr("reservoir");

        implementation = new ACTXToken();
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector, treasury, reservoir, 200, 10_000_000 * 10 ** 18
        );
        proxy = new ERC1967Proxy(address(implementation), initData);
        token = ACTXToken(address(proxy));
    }

    function test_Upgrade_Success() public {
        // Deploy new implementation
        ACTXToken newImplementation = new ACTXToken();

        // Upgrade
        vm.prank(treasury);
        token.upgradeToAndCall(address(newImplementation), "");

        // Version should be incremented
        assertEq(token.version(), 2);
    }

    function test_Upgrade_RevertNotUpgrader() public {
        ACTXToken newImplementation = new ACTXToken();
        address nonAdmin = makeAddr("nonAdmin");

        vm.prank(nonAdmin);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImplementation), "");
    }

    function test_Upgrade_PreservesState() public {
        // Distribute some rewards first
        address user = makeAddr("user");
        // Note: Treasury already has REWARD_MANAGER_ROLE from initialization, no need to grant
        
        vm.prank(treasury);
        token.distributeReward(user, 1000 * 10 ** 18);

        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 totalDistributedBefore = token.totalRewardsDistributed();

        // Upgrade
        ACTXToken newImplementation = new ACTXToken();
        vm.prank(treasury);
        token.upgradeToAndCall(address(newImplementation), "");

        // State should be preserved
        assertEq(token.balanceOf(user), userBalanceBefore);
        assertEq(token.totalRewardsDistributed(), totalDistributedBefore);
    }
}

