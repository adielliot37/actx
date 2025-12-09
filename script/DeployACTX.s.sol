// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ACTXToken} from "../src/ACTXToken.sol";
import {ACTXAirdrop} from "../src/Airdrop.sol";
import {ACTXVesting} from "../src/Vesting.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployACTX
 * @notice Deployment script for the ACT.X Token ecosystem
 * @dev Deploys ACTXToken (proxied), Airdrop, and Vesting contracts
 *
 * Usage:
 * 1. Set environment variables:
 *    - PRIVATE_KEY: Deployer private key
 *    - TREASURY_ADDRESS: Multi-sig treasury address
 *    - RESERVOIR_ADDRESS: Tax reservoir address
 *    - SEPOLIA_RPC_URL: RPC endpoint
 *
 * 2. Deploy to Sepolia:
 *    forge script script/DeployACTX.s.sol:DeployACTX --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 *
 * 3. Deploy to Base:
 *    forge script script/DeployACTX.s.sol:DeployACTX --rpc-url $BASE_RPC_URL --broadcast --verify
 */
contract DeployACTX is Script {
    // ============ Configuration ============

    /// @notice Initial tax rate in basis points (2%)
    uint256 public constant INITIAL_TAX_RATE_BP = 200;

    /// @notice Initial reward pool allocation (10% of supply)
    uint256 public constant REWARD_POOL_ALLOCATION = 10_000_000 * 10 ** 18;

    /// @notice Airdrop allocation (5% of supply)
    uint256 public constant AIRDROP_ALLOCATION = 5_000_000 * 10 ** 18;

    /// @notice Vesting allocation for team/advisors (15% of supply)
    uint256 public constant VESTING_ALLOCATION = 15_000_000 * 10 ** 18;

    // ============ Deployed Addresses ============

    ACTXToken public implementation;
    ERC1967Proxy public proxy;
    ACTXToken public token;
    ACTXAirdrop public airdrop;
    ACTXVesting public vesting;

    function run() external {
        // Load configuration from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address reservoir = vm.envAddress("RESERVOIR_ADDRESS");

        console.log("=== ACT.X Token Deployment ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Treasury:", treasury);
        console.log("Reservoir:", reservoir);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ACTXToken Implementation
        console.log("Deploying ACTXToken implementation...");
        implementation = new ACTXToken();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector,
            treasury,
            reservoir,
            INITIAL_TAX_RATE_BP,
            REWARD_POOL_ALLOCATION
        );

        // 3. Deploy ERC1967 Proxy
        console.log("Deploying proxy...");
        proxy = new ERC1967Proxy(address(implementation), initData);
        token = ACTXToken(address(proxy));
        console.log("Proxy deployed at:", address(proxy));
        console.log("Token initialized with:");
        console.log("  - Tax Rate:", INITIAL_TAX_RATE_BP, "basis points");
        console.log("  - Reward Pool:", REWARD_POOL_ALLOCATION / 10 ** 18, "ACTX");

        // 4. Deploy Airdrop Contract
        console.log("");
        console.log("Deploying Airdrop contract...");
        airdrop = new ACTXAirdrop(address(token), treasury);
        console.log("Airdrop deployed at:", address(airdrop));

        // 5. Deploy Vesting Contract
        console.log("");
        console.log("Deploying Vesting contract...");
        vesting = new ACTXVesting(address(token), treasury);
        console.log("Vesting deployed at:", address(vesting));

        vm.stopBroadcast();

        // Print summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (Token):", address(proxy));
        console.log("Airdrop:", address(airdrop));
        console.log("Vesting:", address(vesting));
        console.log("");
        console.log("=== Post-Deployment Actions ===");
        console.log("1. Transfer ACTX tokens to Airdrop contract for distribution");
        console.log("2. Transfer ACTX tokens to Vesting contract for team/advisors");
        console.log("3. Create airdrop campaigns via Airdrop.createCampaign()");
        console.log("4. Create vesting schedules via Vesting.createVestingSchedule()");
        console.log("5. Grant REWARD_MANAGER_ROLE to backend service address");
    }
}

/**
 * @title DeployACTXLocal
 * @notice Deployment script for local testing (Anvil)
 * @dev Uses predetermined addresses for testing
 */
contract DeployACTXLocal is Script {
    function run() external {
        // Use default Anvil accounts
        uint256 deployerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerKey);

        // For local testing, deployer is also treasury and reservoir
        address treasury = deployer;
        address reservoir = address(0x2);

        console.log("=== Local Deployment (Anvil) ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy implementation
        ACTXToken implementation = new ACTXToken();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            ACTXToken.initialize.selector,
            treasury,
            reservoir,
            200, // 2% tax
            10_000_000 * 10 ** 18 // 10M reward pool
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Deploy supporting contracts
        ACTXAirdrop airdrop = new ACTXAirdrop(address(proxy), treasury);
        ACTXVesting vesting = new ACTXVesting(address(proxy), treasury);

        vm.stopBroadcast();

        console.log("Token:", address(proxy));
        console.log("Airdrop:", address(airdrop));
        console.log("Vesting:", address(vesting));
    }
}

/**
 * @title UpgradeACTX
 * @notice Script for upgrading the ACT.X token contract
 */
contract UpgradeACTX is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        console.log("=== ACT.X Token Upgrade ===");
        console.log("Proxy:", proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        ACTXToken newImplementation = new ACTXToken();
        console.log("New implementation:", address(newImplementation));

        // Upgrade proxy
        ACTXToken token = ACTXToken(proxyAddress);
        token.upgradeToAndCall(address(newImplementation), "");

        console.log("Upgrade complete. New version:", token.version());

        vm.stopBroadcast();
    }
}

/**
 * @title ConfigureACTX
 * @notice Post-deployment configuration script
 */
contract ConfigureACTX is Script {
    function run() external {
        uint256 adminKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address airdropAddress = vm.envAddress("AIRDROP_ADDRESS");
        address vestingAddress = vm.envAddress("VESTING_ADDRESS");
        address rewardManagerAddress = vm.envAddress("REWARD_MANAGER_ADDRESS");

        ACTXToken token = ACTXToken(proxyAddress);

        vm.startBroadcast(adminKey);

        // Grant reward manager role
        token.grantRole(token.REWARD_MANAGER_ROLE(), rewardManagerAddress);
        console.log("Granted REWARD_MANAGER_ROLE to:", rewardManagerAddress);

        // Fund airdrop contract
        uint256 airdropFunding = 5_000_000 * 10 ** 18;
        token.transfer(airdropAddress, airdropFunding);
        console.log("Funded Airdrop with:", airdropFunding / 10 ** 18, "ACTX");

        // Fund vesting contract
        uint256 vestingFunding = 15_000_000 * 10 ** 18;
        token.transfer(vestingAddress, vestingFunding);
        console.log("Funded Vesting with:", vestingFunding / 10 ** 18, "ACTX");

        vm.stopBroadcast();

        console.log("Configuration complete!");
    }
}

