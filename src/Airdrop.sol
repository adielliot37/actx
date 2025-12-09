// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title ACTXAirdrop
/// @notice Merkle-tree based airdrop contract with KYC gating support
contract ACTXAirdrop is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct Campaign {
        bytes32 merkleRoot;
        uint256 totalAllocation;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        string description;
    }

    IERC20 public immutable actxToken;
    uint256 public campaignCount;
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    mapping(uint256 => mapping(address => uint256)) public claimedAmount;
    address public kycRegistry;
    mapping(address => bool) public isKYCVerified;
    bool public kycRequired;

    event CampaignCreated(uint256 indexed campaignId, bytes32 merkleRoot, uint256 totalAllocation, uint256 startTime, uint256 endTime, string description);
    event TokensClaimed(uint256 indexed campaignId, address indexed claimant, uint256 amount, uint256 timestamp);
    event CampaignDeactivated(uint256 indexed campaignId);
    event TokensRecovered(uint256 indexed campaignId, uint256 amount);
    event KYCStatusUpdated(address indexed account, bool status);
    event KYCRequirementUpdated(bool required);
    event MerkleRootUpdated(uint256 indexed campaignId, bytes32 oldRoot, bytes32 newRoot);

    error InvalidCampaign();
    error CampaignNotActive();
    error CampaignNotStarted();
    error CampaignEnded();
    error AlreadyClaimed();
    error InvalidProof();
    error InvalidAllocation();
    error KYCNotVerified();
    error InsufficientBalance();
    error ZeroAddress();
    error InvalidTimeRange();

    constructor(address _actxToken, address _owner) Ownable(_owner) {
        if (_actxToken == address(0)) revert ZeroAddress();
        actxToken = IERC20(_actxToken);
    }

    function createCampaign(
        bytes32 merkleRoot,
        uint256 totalAllocation,
        uint256 startTime,
        uint256 endTime,
        string calldata description
    ) external onlyOwner returns (uint256 campaignId) {
        if (merkleRoot == bytes32(0)) revert InvalidProof();
        if (totalAllocation == 0) revert InvalidAllocation();
        if (startTime >= endTime) revert InvalidTimeRange();
        if (endTime <= block.timestamp) revert InvalidTimeRange();

        uint256 currentBalance = actxToken.balanceOf(address(this));
        uint256 totalCommitted = _getTotalCommittedTokens();
        if (currentBalance < totalCommitted + totalAllocation) {
            revert InsufficientBalance();
        }

        campaignId = campaignCount++;
        campaigns[campaignId] = Campaign({
            merkleRoot: merkleRoot,
            totalAllocation: totalAllocation,
            totalClaimed: 0,
            startTime: startTime,
            endTime: endTime,
            isActive: true,
            description: description
        });

        emit CampaignCreated(campaignId, merkleRoot, totalAllocation, startTime, endTime, description);
    }

    function updateMerkleRoot(uint256 campaignId, bytes32 newMerkleRoot) external onlyOwner {
        if (campaignId >= campaignCount) revert InvalidCampaign();
        if (newMerkleRoot == bytes32(0)) revert InvalidProof();

        Campaign storage campaign = campaigns[campaignId];
        bytes32 oldRoot = campaign.merkleRoot;
        campaign.merkleRoot = newMerkleRoot;
        emit MerkleRootUpdated(campaignId, oldRoot, newMerkleRoot);
    }

    function deactivateCampaign(uint256 campaignId) external onlyOwner {
        if (campaignId >= campaignCount) revert InvalidCampaign();
        campaigns[campaignId].isActive = false;
        emit CampaignDeactivated(campaignId);
    }

    function claim(uint256 campaignId, uint256 amount, bytes32[] calldata merkleProof) external nonReentrant whenNotPaused {
        _claim(campaignId, msg.sender, amount, merkleProof);
    }

    function claimFor(uint256 campaignId, address claimant, uint256 amount, bytes32[] calldata merkleProof) external nonReentrant whenNotPaused {
        if (claimant == address(0)) revert ZeroAddress();
        _claim(campaignId, claimant, amount, merkleProof);
    }

    function _claim(uint256 campaignId, address claimant, uint256 amount, bytes32[] calldata merkleProof) internal {
        if (campaignId >= campaignCount) revert InvalidCampaign();

        Campaign storage campaign = campaigns[campaignId];
        if (!campaign.isActive) revert CampaignNotActive();
        if (block.timestamp < campaign.startTime) revert CampaignNotStarted();
        if (block.timestamp > campaign.endTime) revert CampaignEnded();
        if (hasClaimed[campaignId][claimant]) revert AlreadyClaimed();
        if (kycRequired && !isKYCVerified[claimant]) revert KYCNotVerified();

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(claimant, amount))));
        if (!MerkleProof.verify(merkleProof, campaign.merkleRoot, leaf)) {
            revert InvalidProof();
        }

        hasClaimed[campaignId][claimant] = true;
        claimedAmount[campaignId][claimant] = amount;
        campaign.totalClaimed += amount;
        actxToken.safeTransfer(claimant, amount);

        emit TokensClaimed(campaignId, claimant, amount, block.timestamp);
    }

    function setKYCRequired(bool required) external onlyOwner {
        kycRequired = required;
        emit KYCRequirementUpdated(required);
    }

    function setKYCStatus(address account, bool status) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        isKYCVerified[account] = status;
        emit KYCStatusUpdated(account, status);
    }

    function batchSetKYCStatus(address[] calldata accounts, bool[] calldata statuses) external onlyOwner {
        require(accounts.length == statuses.length, "ACTXAirdrop: arrays length mismatch");
        for (uint256 i = 0; i < accounts.length;) {
            if (accounts[i] == address(0)) revert ZeroAddress();
            isKYCVerified[accounts[i]] = statuses[i];
            emit KYCStatusUpdated(accounts[i], statuses[i]);
            unchecked { ++i; }
        }
    }

    function recoverUnclaimedTokens(uint256 campaignId) external onlyOwner {
        if (campaignId >= campaignCount) revert InvalidCampaign();

        Campaign storage campaign = campaigns[campaignId];
        if (block.timestamp <= campaign.endTime) revert CampaignNotActive();

        uint256 unclaimed = campaign.totalAllocation - campaign.totalClaimed;
        if (unclaimed == 0) revert InvalidAllocation();

        campaign.totalClaimed = campaign.totalAllocation;
        campaign.isActive = false;
        actxToken.safeTransfer(owner(), unclaimed);

        emit TokensRecovered(campaignId, unclaimed);
    }

    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    function getCampaign(uint256 campaignId) external view returns (
        bytes32 merkleRoot,
        uint256 totalAllocation,
        uint256 totalClaimed,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        string memory description
    ) {
        if (campaignId >= campaignCount) revert InvalidCampaign();
        Campaign memory campaign = campaigns[campaignId];
        return (campaign.merkleRoot, campaign.totalAllocation, campaign.totalClaimed, campaign.startTime, campaign.endTime, campaign.isActive, campaign.description);
    }

    function canClaim(uint256 campaignId, address claimant, uint256 amount, bytes32[] calldata merkleProof) external view returns (bool canClaim, string memory reason) {
        if (campaignId >= campaignCount) return (false, "Invalid campaign");

        Campaign memory campaign = campaigns[campaignId];
        if (!campaign.isActive) return (false, "Campaign not active");
        if (block.timestamp < campaign.startTime) return (false, "Campaign not started");
        if (block.timestamp > campaign.endTime) return (false, "Campaign ended");
        if (hasClaimed[campaignId][claimant]) return (false, "Already claimed");
        if (kycRequired && !isKYCVerified[claimant]) return (false, "KYC not verified");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(claimant, amount))));
        if (!MerkleProof.verify(merkleProof, campaign.merkleRoot, leaf)) {
            return (false, "Invalid proof");
        }

        return (true, "Eligible to claim");
    }

    function _getTotalCommittedTokens() internal view returns (uint256 total) {
        for (uint256 i = 0; i < campaignCount;) {
            if (campaigns[i].isActive && block.timestamp <= campaigns[i].endTime) {
                total += campaigns[i].totalAllocation - campaigns[i].totalClaimed;
            }
            unchecked { ++i; }
        }
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
