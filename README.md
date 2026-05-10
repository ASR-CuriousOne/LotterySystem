# Veritas

<img width="1600" height="745" alt="image" src="https://github.com/user-attachments/assets/2e59d07f-4b10-4595-971d-eedb43fe30a4" />


> Project 4: Decentralized Lottery System

Veritas is a multi-tiered, provably fair decentralized lottery system built for the Ethereum blockchain. Moving beyond basic commit-reveal schemes, we engineered an institutional-grade, fully audited smart contract architecture utilizing OpenZeppelin UUPS Proxies, Chainlink VRF v2.5, and Chainlink Automation (Keepers).

Find the [Project Report](./reports/Project4_BitBoyz_Report.pdf) here. This is our [Demo Video](https://drive.google.com/file/d/12UijotLsn_K3qHPDedxYU01li-422RJ8/view). If the link is not accessible, the repository contains the actual [file](./demo_video.mp4) as well.

## The Team

| Name                   | Roll Number |
| :--------------------- | :---------- |
| Arnav Kumar            | 240001013   |
| Aryaman Awanish Tiwari | 240001014   |
| Ayush Singh Rana       | 240001015   |
| Hrishabh Mittal        | 240001035   |
| Prabandham Sriniketan  | 240001052   |
| Yash Arya Saxena       | 240001081   |

## System Architecture

The project is structured into three progressive iterations of lottery logic:

1.  Lottery.sol (Base): The baseline implementation using a manual Commit-Reveal scheme to satisfy strict rubric parameters. It utilizes dynamic arrays and string-based reverts to establish a gas-cost baseline.
2.  LotteryVRF.sol (Intermediate): An experimental upgraded version utilizing Chainlink VRF to prevent miner manipulation and MEV attacks.
3.  LotteryEX.sol (Enterprise): Our flagship "extended" multi-round architecture. It is fully autonomous, utilizing Chainlink Automation (Keepers) to natively trigger draws and manage time-based refund fallbacks. It is structured behind an ERC1967 UUPS Proxy for upgradeability.

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

### Setup & Compilation

```bash
# Clone the repository
git clone https://github.com/ASR-CuriousOne/LotterySystem
cd LotterySystem

# Install OpenZeppelin and dependencies
forge install

# Compile contracts
forge build
```

### Testing & Coverage

We maintain full line, branch, and function coverage across all contracts (Lottery.sol, LotteryVRF.sol, LotteryEX.sol).

```bash
# Run the test suites
forge test

# Generate the gas report
forge test --gas-report

# View the coverage report
forge coverage
```

## Deployment Pipeline

### Local Deployment (Anvil)

To test the deployment and integrations locally, spin up a local Foundry node:

```bash
anvil
```

Note any of the private keys displayed in the terminal. In a separate terminal, deploy the contracts using one of those pre-funded default private keys:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --private-key <YOUR_PRIVATE_KEY> --broadcast
```

### Live Deployment (Sepolia Testnet)

To deploy the contract to a live network and verify the source code, copy the provided example environment file and insert your own API and wallet keys:

```bash
cp .env.example .env
```

Load your environment variables and execute the deployment script, passing the variables explicitly via command-line flags:

```bash
source .env
forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

## Gas Optimizations & EVM Architecture

By comparing Lottery.sol to LotteryEX.sol, we successfully implemented and benchmarked the following EVM optimizations. All metrics are derived from Foundry median execution costs simulating a 256-ticket round.

### 1. Storage Compression

- The Vulnerability: Lottery.sol pushes addresses to a dynamic array, requiring an SSTORE operation for both the data and the array length (costing 20,000+ gas per ticket).
- The Optimization: LotteryEX.sol utilizes a bitmapped storage pattern using a single uint256 integer. When a user buys a ticket, a bitwise OR operation flips a specific bit, locking the data footprint to a single 32-byte slot regardless of how many tickets are sold.

### 2. Immutable State Variables

- The Optimization: Refactoring `ticketPrice` to an immutable variable in the base contract embeds the value directly into the bytecode. This replaces an expensive SLOAD operation (100 gas) with a highly efficient PUSH operation (3 gas).
- Net Savings: Saves ~2,000 gas per transaction, preventing over 512,000 gas in overhead across a fully sold-out round.

### 3. EVM Struct Packing

- The Optimization: We packed the `Round` struct in LotteryEX.sol to fit perfectly into exactly two 32-byte EVM slots (Slot 0 for the 32-byte bitmap, Slot 1 combining `address winner`, `uint16 ticketsSold`, and `Phase phase`).
- Impact: Updating the ticket count and phase simultaneously now costs a single SSTORE execution instead of two.

### 4. Custom Errors

- The Vulnerability: Standard `require(condition, "String message")` statements bloat contract bytecode by storing long ASCII strings.
- The Optimization: Upgrading to Solidity 0.8.4+ custom errors encodes failures as 4-byte ABI selectors. Despite adding Keepers, VRF v2.5, proxies, and treasury routing, custom errors kept LotteryEX.sol strictly below the 24.5 KB EIP-170 limit (deployed at 15.8 KB).

### 5. Memory Caching

- The Optimization: When emitting events (`WinnerDrawn`), referencing state variables directly forces an SLOAD. We cache heavy variables into local memory before processing math or emitting events, bypassing storage reads entirely.

### 6. The "Fail-Fast" Keeper Architecture

- The Optimization: `checkUpkeep()` evaluates the cheapest and most restrictive condition first (`currentPhase != Phase.Open`). Because the phase is packed into the heavily-accessed Slot 1, it instantly aborts invalid checks, saving the Keeper network from simulating heavier block timestamp logic and lowering operational costs.

## Security Audit Pipeline

To ensure professional rigor, our repository utilizes a fully containerized DevSecOps security toolchain.

### Tools Deployed

- Slither: Static analysis for reentrancy and syntax vulnerability patterns.
- Mythril: Symbolic execution for deep EVM branch analysis.
- Echidna: Property-based fuzzing and invariant testing.
- Surya: Visual architecture graphing.

### Audit Results

- Foundry Invariants: Executed 10,000 runs resulting in over 4.9 million reverted state mutations, proving our checks-effects-interactions (CEI) implementations safely prevent pool draining.
- Echidna Fuzzing: Executed 3,000,000+ total sequences (1M each for Base, VRF, and EX). The fuzzer reached over 5,000 unique EVM instructions in LotteryEX, failing to break the 256-ticket hard cap, hijack round IDs, or breach phase enum boundaries.
- Static Analysis: All Mythril and Slither output logs have been verified. Mythril SWC-101 in LotteryEX and SWC-107 in LotteryVRF were audited and confirmed as false-positives resulting from 0.8.x comparison-reverts and official Chainlink Oracle callback routing.

### Run the Local Audit

```bash
# Build the auditor image
docker build -t auditor .

# Create and run the tester container
docker create -it --name tester -v "$(pwd):/workspace/LotterySystem" auditor
docker start -ai tester
```

## Tech Stack & Standards

- Language: Solidity 0.8.20 & 0.8.22 (UUPS constraints)
- Architecture: OpenZeppelin Ownable2Step, ReentrancyGuard, ERC1967Proxy, UUPSUpgradeable
- Oracles: Chainlink VRF v2.5 & Chainlink Automation (Keepers)
- Documentation: Strict NatSpec compliance
- Frontend: Next.js, TypeScript, Wagmi + Viem for Web3, Tailwind CSS

Veritas: _Vires in Numeris_ (Strength in Numbers).
