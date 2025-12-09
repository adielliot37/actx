// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ACTXToken} from "../src/ACTXToken.sol";
import {ACTXAirdrop} from "../src/Airdrop.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SimpleMerkle
 * @notice Simple merkle tree implementation for testing
 */
library SimpleMerkle {
    function hashLeaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    }

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}

/**
 * @title ACTXAirdropTest
 * @notice Comprehensive test suite for ACT.X Airdrop contract
 */
contract ACTXAirdropTest is Test {
    using SimpleMerkle for *;

    ACTXToken public token;
    ACTXAirdrop public airdrop;

    address public treasury;
    address public reservoir;
    address public owner;

    address public user1;
    address public user2;
    address public user3;
    address public user4;

    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant AIRDROP_ALLOCATION = 5_000_000 * 10 ** 18;

    // Airdrop amounts
    uint256 public amount1 = 1000 * 10 ** 18;
    uint256 public amount2 = 2000 * 10 ** 18;
    uint256 public amount3 = 3000 * 10 ** 18;
    uint256 public amount4 = 4000 * 10 ** 18;

    // Merkle tree data
    bytes32 public merkleRoot;
    bytes32[] public leaves;

    event TokensClaimed(uint256 indexed campaignId, address indexed claimant, uint256 amount, uint256 timestamp);
    event CampaignCreated(
        uint256 indexed campaignId,
        bytes32 merkleRoot,
        uint256 totalAllocation,
        uint256 startTime,
        uint256 endTime,
        string description
    );

    function setUp() public {
        // Setup addresses
        treasury = makeAddr("treasury");
        reservoir = makeAddr("reservoir");
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");

        // Deploy token
        ACTXToken implementation = new ACTXToken();
        bytes memory initData =
            abi.encodeWithSelector(ACTXToken.initialize.selector, treasury, reservoir, 200, 10_000_000 * 10 ** 18);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = ACTXToken(address(proxy));

        // Deploy airdrop contract
        airdrop = new ACTXAirdrop(address(token), owner);

        // Build merkle tree
        _buildMerkleTree();

        // Fund airdrop contract (treasury is tax exempt, so full amount transferred)
        vm.prank(treasury);
        token.transfer(address(airdrop), AIRDROP_ALLOCATION);

        // Set airdrop contract as tax exempt so users receive full amounts
        vm.prank(treasury);
        token.setTaxExemption(address(airdrop), true);
    }

    function _buildMerkleTree() internal {
        // Create leaves
        leaves = new bytes32[](4);
        leaves[0] = SimpleMerkle.hashLeaf(user1, amount1);
        leaves[1] = SimpleMerkle.hashLeaf(user2, amount2);
        leaves[2] = SimpleMerkle.hashLeaf(user3, amount3);
        leaves[3] = SimpleMerkle.hashLeaf(user4, amount4);

        // Build tree (simplified 4-leaf tree)
        bytes32 hash01 = SimpleMerkle.hashPair(leaves[0], leaves[1]);
        bytes32 hash23 = SimpleMerkle.hashPair(leaves[2], leaves[3]);
        merkleRoot = SimpleMerkle.hashPair(hash01, hash23);
    }

    function _getProofForUser1() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1]; // sibling
        proof[1] = SimpleMerkle.hashPair(leaves[2], leaves[3]); // uncle
        return proof;
    }

    function _getProofForUser2() internal view returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[0]; // sibling
        proof[1] = SimpleMerkle.hashPair(leaves[2], leaves[3]); // uncle
        return proof;
    }

    // ============ Campaign Creation Tests ============

    function test_CreateCampaign_Success() public {
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit CampaignCreated(0, merkleRoot, AIRDROP_ALLOCATION, startTime, endTime, "Genesis Airdrop");

        uint256 campaignId =
            airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, startTime, endTime, "Genesis Airdrop");

        assertEq(campaignId, 0);
        assertEq(airdrop.campaignCount(), 1);

        (
            bytes32 root,
            uint256 allocation,
            uint256 claimed,
            uint256 start,
            uint256 end,
            bool active,
            string memory desc
        ) = airdrop.getCampaign(0);

        assertEq(root, merkleRoot);
        assertEq(allocation, AIRDROP_ALLOCATION);
        assertEq(claimed, 0);
        assertEq(start, startTime);
        assertEq(end, endTime);
        assertTrue(active);
        assertEq(desc, "Genesis Airdrop");
    }

    function test_CreateCampaign_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");
    }

    function test_CreateCampaign_RevertInvalidTimeRange() public {
        vm.prank(owner);
        vm.expectRevert(ACTXAirdrop.InvalidTimeRange.selector);
        airdrop.createCampaign(
            merkleRoot,
            AIRDROP_ALLOCATION,
            block.timestamp + 30 days, // start after end
            block.timestamp,
            "Test"
        );
    }

    function test_CreateCampaign_RevertInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(ACTXAirdrop.InsufficientBalance.selector);
        airdrop.createCampaign(
            merkleRoot,
            AIRDROP_ALLOCATION * 2, // More than contract has
            block.timestamp,
            block.timestamp + 30 days,
            "Test"
        );
    }

    // ============ Claim Tests ============

    function test_Claim_Success() public {
        // Create campaign
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32[] memory proof = _getProofForUser1();

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit TokensClaimed(0, user1, amount1, block.timestamp);
        airdrop.claim(0, amount1, proof);

        assertEq(token.balanceOf(user1), balanceBefore + amount1);
        assertTrue(airdrop.hasClaimed(0, user1));
        assertEq(airdrop.claimedAmount(0, user1), amount1);
    }

    function test_Claim_RevertAlreadyClaimed() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        airdrop.claim(0, amount1, proof);

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.AlreadyClaimed.selector);
        airdrop.claim(0, amount1, proof);
    }

    function test_Claim_RevertCampaignNotStarted() public {
        vm.prank(owner);
        airdrop.createCampaign(
            merkleRoot, AIRDROP_ALLOCATION, block.timestamp + 1 days, block.timestamp + 30 days, "Test"
        );

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.CampaignNotStarted.selector);
        airdrop.claim(0, amount1, proof);
    }

    function test_Claim_RevertCampaignEnded() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        // Warp past end time
        vm.warp(block.timestamp + 31 days);

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.CampaignEnded.selector);
        airdrop.claim(0, amount1, proof);
    }

    function test_Claim_RevertInvalidProof() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        // Use wrong proof
        bytes32[] memory wrongProof = new bytes32[](2);
        wrongProof[0] = bytes32(uint256(1));
        wrongProof[1] = bytes32(uint256(2));

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.InvalidProof.selector);
        airdrop.claim(0, amount1, wrongProof);
    }

    function test_Claim_RevertWrongAmount() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.InvalidProof.selector);
        airdrop.claim(0, amount2, proof); // Wrong amount for user1
    }

    // ============ ClaimFor Tests ============

    function test_ClaimFor_Success() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32[] memory proof = _getProofForUser1();

        // Anyone can claim for user1
        vm.prank(user2);
        airdrop.claimFor(0, user1, amount1, proof);

        assertEq(token.balanceOf(user1), amount1);
        assertTrue(airdrop.hasClaimed(0, user1));
    }

    // ============ KYC Tests ============

    function test_KYCRequired_RevertIfNotVerified() public {
        vm.startPrank(owner);
        airdrop.setKYCRequired(true);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");
        vm.stopPrank();

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.KYCNotVerified.selector);
        airdrop.claim(0, amount1, proof);
    }

    function test_KYCRequired_SuccessIfVerified() public {
        vm.startPrank(owner);
        airdrop.setKYCRequired(true);
        airdrop.setKYCStatus(user1, true);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");
        vm.stopPrank();

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        airdrop.claim(0, amount1, proof);

        assertEq(token.balanceOf(user1), amount1);
    }

    function test_BatchSetKYCStatus() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;

        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = false;

        vm.prank(owner);
        airdrop.batchSetKYCStatus(accounts, statuses);

        assertTrue(airdrop.isKYCVerified(user1));
        assertTrue(airdrop.isKYCVerified(user2));
        assertFalse(airdrop.isKYCVerified(user3));
    }

    // ============ Campaign Management Tests ============

    function test_DeactivateCampaign() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        vm.prank(owner);
        airdrop.deactivateCampaign(0);

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        vm.expectRevert(ACTXAirdrop.CampaignNotActive.selector);
        airdrop.claim(0, amount1, proof);
    }

    function test_UpdateMerkleRoot() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32 newRoot = keccak256("new root");

        vm.prank(owner);
        airdrop.updateMerkleRoot(0, newRoot);

        (bytes32 root,,,,,, ) = airdrop.getCampaign(0);
        assertEq(root, newRoot);
    }

    // ============ Token Recovery Tests ============

    function test_RecoverUnclaimedTokens() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        // Some users claim
        bytes32[] memory proof1 = _getProofForUser1();
        vm.prank(user1);
        airdrop.claim(0, amount1, proof1);

        // Warp past end
        vm.warp(block.timestamp + 31 days);

        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        airdrop.recoverUnclaimedTokens(0);

        uint256 recovered = token.balanceOf(owner) - ownerBalanceBefore;
        assertEq(recovered, AIRDROP_ALLOCATION - amount1);
    }

    // ============ View Function Tests ============

    function test_CanClaim_Eligible() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32[] memory proof = _getProofForUser1();

        (bool canClaim, string memory reason) = airdrop.canClaim(0, user1, amount1, proof);

        assertTrue(canClaim);
        assertEq(reason, "Eligible to claim");
    }

    function test_CanClaim_AlreadyClaimed() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        airdrop.claim(0, amount1, proof);

        (bool canClaim, string memory reason) = airdrop.canClaim(0, user1, amount1, proof);

        assertFalse(canClaim);
        assertEq(reason, "Already claimed");
    }

    // ============ Pause Tests ============

    function test_Pause_BlocksClaims() public {
        vm.prank(owner);
        airdrop.createCampaign(merkleRoot, AIRDROP_ALLOCATION, block.timestamp, block.timestamp + 30 days, "Test");

        vm.prank(owner);
        airdrop.pause();

        bytes32[] memory proof = _getProofForUser1();

        vm.prank(user1);
        vm.expectRevert();
        airdrop.claim(0, amount1, proof);
    }
}

