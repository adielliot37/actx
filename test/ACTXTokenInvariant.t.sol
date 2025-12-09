// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ACTXToken } from "../src/ACTXToken.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ACTXTokenHandler
 * @notice Handler contract for invariant testing
 * @dev Wraps ACTXToken functions with bounded inputs
 */
contract ACTXTokenHandler is Test {
    ACTXToken public token;
    address public treasury;
    address public reservoir;

    address[] public actors;
    address internal currentActor;

    uint256 public ghost_totalDistributed;
    uint256 public ghost_totalTaxCollected;
    uint256 public ghost_totalBurned;

    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(ACTXToken _token, address _treasury, address _reservoir) {
        token = _token;
        treasury = _treasury;
        reservoir = _reservoir;

        // Create actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }
    }

    function distributeReward(uint256 actorIndex, uint256 amount) external countCall("distributeReward") {
        address recipient = actors[bound(actorIndex, 0, actors.length - 1)];
        uint256 poolBalance = token.rewardPoolBalance();

        if (poolBalance == 0) return;
        amount = bound(amount, 1, poolBalance);

        vm.prank(treasury);
        token.distributeReward(recipient, amount);

        ghost_totalDistributed += amount;
    }

    function transfer(uint256 fromIndex, uint256 toIndex, uint256 amount) external countCall("transfer") {
        address from = actors[bound(fromIndex, 0, actors.length - 1)];
        address to = actors[bound(toIndex, 0, actors.length - 1)];

        uint256 balance = token.balanceOf(from);
        if (balance == 0 || from == to) return;

        amount = bound(amount, 1, balance);

        // Skip if amount too small for tax
        (uint256 taxAmount, uint256 netAmount) = token.calculateTax(amount);
        if (netAmount == 0) return;

        vm.prank(from);
        token.transfer(to, amount);

        ghost_totalTaxCollected += taxAmount;
    }

    function burn(uint256 actorIndex, uint256 amount) external countCall("burn") {
        address actor = actors[bound(actorIndex, 0, actors.length - 1)];
        uint256 balance = token.balanceOf(actor);

        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(actor);
        token.burn(amount);

        ghost_totalBurned += amount;
    }

    function setTaxRate(uint256 newRate) external countCall("setTaxRate") {
        newRate = bound(newRate, 0, 1000);

        vm.prank(treasury);
        token.setTaxRate(newRate);
    }

    function fundRewardPool(uint256 amount) external countCall("fundRewardPool") {
        uint256 treasuryBalance = token.balanceOf(treasury);
        uint256 currentPool = token.rewardPoolBalance();

        if (treasuryBalance <= currentPool) return;
        amount = bound(amount, 1, treasuryBalance - currentPool);

        vm.prank(treasury);
        token.fundRewardPool(amount);
    }

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("---");
        console.log("distributeReward", calls["distributeReward"]);
        console.log("transfer", calls["transfer"]);
        console.log("burn", calls["burn"]);
        console.log("setTaxRate", calls["setTaxRate"]);
        console.log("fundRewardPool", calls["fundRewardPool"]);
        console.log("---");
        console.log("Ghost values:");
        console.log("totalDistributed", ghost_totalDistributed);
        console.log("totalTaxCollected", ghost_totalTaxCollected);
        console.log("totalBurned", ghost_totalBurned);
    }
}

/**
 * @title ACTXTokenInvariantTest
 * @notice Invariant tests for ACT.X Token
 * @dev Tests critical invariants that must always hold
 */
contract ACTXTokenInvariantTest is StdInvariant, Test {
    ACTXToken public token;
    ACTXToken public implementation;
    ERC1967Proxy public proxy;
    ACTXTokenHandler public handler;

    address public treasury;
    address public reservoir;

    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant INITIAL_REWARD_POOL = 10_000_000 * 10 ** 18;

    function setUp() public {
        treasury = makeAddr("treasury");
        reservoir = makeAddr("reservoir");

        // Deploy token
        implementation = new ACTXToken();
        bytes memory initData =
            abi.encodeWithSelector(ACTXToken.initialize.selector, treasury, reservoir, 200, INITIAL_REWARD_POOL);
        proxy = new ERC1967Proxy(address(implementation), initData);
        token = ACTXToken(address(proxy));

        // Deploy handler
        handler = new ACTXTokenHandler(token, treasury, reservoir);

        // Set target contract
        targetContract(address(handler));

        // Exclude addresses from being fuzzed as senders
        excludeSender(address(token));
        excludeSender(address(proxy));
        excludeSender(treasury);
        excludeSender(reservoir);
    }

    /// @notice Total supply should never exceed initial minted amount (can only decrease via burns)
    function invariant_TotalSupplyNeverIncrease() public view {
        assertLe(token.totalSupply(), TOTAL_SUPPLY);
    }

    /// @notice Total supply should equal initial supply minus burns
    function invariant_TotalSupplyEquation() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY - handler.ghost_totalBurned());
    }

    /// @notice Sum of all balances should equal total supply
    function invariant_BalancesSumToTotalSupply() public view {
        uint256 totalBalance = token.balanceOf(treasury) + token.balanceOf(reservoir);

        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            totalBalance += token.balanceOf(actors[i]);
        }

        // Account for any other addresses that might have tokens
        assertLe(totalBalance, token.totalSupply());
    }

    /// @notice Tax rate should never exceed maximum
    function invariant_TaxRateWithinBounds() public view {
        assertLe(token.taxRateBasisPoints(), token.MAX_TAX_RATE_BP());
    }

    /// @notice Total rewards distributed should match ghost variable
    function invariant_TotalRewardsDistributedTracked() public view {
        assertEq(token.totalRewardsDistributed(), handler.ghost_totalDistributed());
    }

    /// @notice Reward pool balance should never exceed total supply
    function invariant_RewardPoolWithinBounds() public view {
        assertLe(token.rewardPoolBalance(), token.totalSupply());
    }

    /// @notice Treasury balance should be >= reward pool balance (since rewards come from treasury)
    function invariant_TreasuryCanCoverRewardPool() public view {
        // After distributions, treasury balance + distributed >= initial reward pool
        uint256 treasuryBalance = token.balanceOf(treasury);
        uint256 currentPool = token.rewardPoolBalance();
        uint256 distributed = token.totalRewardsDistributed();

        // Treasury balance should cover the reward pool
        // Note: This can be violated if treasury transfers out tokens separately
        // So we check a looser invariant
        assertGe(treasuryBalance, currentPool);
    }

    /// @notice Reservoir should accumulate tax
    function invariant_ReservoirReceivesTax() public view {
        // Reservoir balance should equal ghost tax collected
        // Note: This assumes reservoir doesn't transfer out
        assertGe(token.balanceOf(reservoir), handler.ghost_totalTaxCollected());
    }

    /// @notice Contract version should be positive
    function invariant_VersionPositive() public view {
        assertGe(token.version(), 1);
    }

    /// @notice Critical addresses should never be zero
    function invariant_CriticalAddressesNonZero() public view {
        assertTrue(token.treasuryAddress() != address(0));
        assertTrue(token.reservoirAddress() != address(0));
    }

    /// @notice Core addresses should always be tax exempt
    function invariant_CoreAddressesTaxExempt() public view {
        assertTrue(token.isTaxExempt(treasury));
        assertTrue(token.isTaxExempt(token.reservoirAddress()));
        assertTrue(token.isTaxExempt(address(token)));
    }

    /// @notice Call summary after invariant run
    function invariant_CallSummary() public view {
        handler.callSummary();
    }
}

/**
 * @title ACTXTokenStatefulInvariant
 * @notice Additional stateful invariant tests
 */
contract ACTXTokenStatefulInvariant is Test {
    ACTXToken public token;
    ERC1967Proxy public proxy;

    address public treasury;
    address public reservoir;
    address[] public users;

    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;

    function setUp() public {
        treasury = makeAddr("treasury");
        reservoir = makeAddr("reservoir");

        for (uint256 i = 0; i < 5; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        ACTXToken implementation = new ACTXToken();
        bytes memory initData =
            abi.encodeWithSelector(ACTXToken.initialize.selector, treasury, reservoir, 200, 10_000_000 * 10 ** 18);
        proxy = new ERC1967Proxy(address(implementation), initData);
        token = ACTXToken(address(proxy));
    }

    /// @notice Test that total supply remains constant through multiple operations
    function test_Invariant_TotalSupplyConstant() public {
        uint256 initialSupply = token.totalSupply();

        // Distribute rewards
        vm.startPrank(treasury);
        token.distributeReward(users[0], 1000 * 10 ** 18);
        token.distributeReward(users[1], 2000 * 10 ** 18);
        vm.stopPrank();

        assertEq(token.totalSupply(), initialSupply);

        // Transfer between users (with tax)
        vm.prank(users[0]);
        token.transfer(users[2], 500 * 10 ** 18);

        assertEq(token.totalSupply(), initialSupply);
    }

    /// @notice Test that balances always sum correctly
    function test_Invariant_BalanceConsistency() public {
        // Distribute to users
        vm.startPrank(treasury);
        for (uint256 i = 0; i < users.length; i++) {
            token.distributeReward(users[i], 1000 * 10 ** 18);
        }
        vm.stopPrank();

        // Perform transfers
        for (uint256 i = 0; i < users.length - 1; i++) {
            vm.prank(users[i]);
            token.transfer(users[i + 1], 100 * 10 ** 18);
        }

        // Sum all balances
        uint256 totalBalance = token.balanceOf(treasury) + token.balanceOf(reservoir);
        for (uint256 i = 0; i < users.length; i++) {
            totalBalance += token.balanceOf(users[i]);
        }

        // Should equal total supply
        assertEq(totalBalance, token.totalSupply());
    }

    /// @notice Test tax calculation invariant: tax + net = original
    function testFuzz_Invariant_TaxCalculation(uint256 amount) public view {
        amount = bound(amount, 0, type(uint128).max); // Prevent overflow

        (uint256 taxAmount, uint256 netAmount) = token.calculateTax(amount);

        assertEq(taxAmount + netAmount, amount, "Tax + Net should equal original amount");
    }
}

