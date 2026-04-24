# Veritas

> Project 4: Decentralized Lottery System

**Veritas** is a multi-tiered, provably fair decentralized lottery system built for the Ethereum blockchain. Moving beyond basic commit-reveal schemes, we implement autonomous, oracle-verified raffle logic using Chainlink VRF and Automation.

## The Team

| Name                       | Roll Number |
| :------------------------- | :---------- |
| **Arnav Kumar**            | 240001013   |
| **Aryaman Awanish Tiwari** | 240001014   |
| **Ayush Singh Rana**       | 240001015   |
| **Hrishabh Mittal**        | 240001035   |
| **Prabandham Sriniketan**  | 240001052   |
| **Yash Arya Saxena**       | 240001081   |

## System Architecture

The project is structured into three progressive iterations of lottery logic:

1.  **Lottery.sol** is the main implementation using a **Commit-Reveal** scheme to satisfy strict rubric parameters. It integrates advanced **O(1) bitmapped ticket tracking** for extreme gas efficiency and a **Pull-Over-Push** vault for secure, DoS-resistant prize claims.
2.  **LotteryVRF.sol** is an experimental upgraded version utilizing **Chainlink VRF** to prevent miner manipulation and MEV attacks.
3.  **LotteryEX.sol** is our **"extended"** multi-round architecture. It is fully autonomous, utilizing **Chainlink Automation (Keepers)** to natively trigger draws and manage time-based refund fallbacks.

## Quick Start

### Prerequisites

- [Foundry](https://www.google.com/search?q=https://book.getfoundry.sh/getting-started/installation) installed.

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

### Running Tests

We maintain **100% Branch and Statement Coverage** across all core contracts.

```bash
# Run the complete test suite
forge test

# Generate a gas report
forge test --gas-report

# View coverage details
forge coverage
```

## Deployment Pipeline

### Local Deployment (Anvil)

To test the deployment and integrations locally, spin up a local Foundry node:

```bash
anvil
```

Note any of the private keys displayed.

In a separate terminal, deploy the contracts using one of these pre-funded default private keys:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url http://localhost:8545 --private-key <YOUR_PRIVATE_KEY> --broadcast
```

### Live Deployment (Sepolia Testnet)

To deploy the contract to a live network, copy the provided example environment file and insert your own API and wallet keys:

```bash
cp .env.example .env
```

Load your environment variables and execute the deployment script, passing the variables explicitly via command-line flags:

```bash
source .env
forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

## Live Deployment & Frontend

- **Frontend DApp:** [Insert Vercel/Netlify Link Here]
- [**Verified Contract (Sepolia)**](https://sepolia.etherscan.io/address/0x15f294cbd5e23f3e47b3d255c0ea13e9a2c771e0)

## Security Audit Pipeline

To ensure academic and professional rigor, we have containerized our entire security toolchain. This allows for a reproducible, military-grade audit of our codebase.

### Tools Included

- **Slither:** Static Analysis for reentrancy and vulnerability patterns.
- **Mythril:** Symbolic execution for deep EVM branch analysis.
- **Echidna:** Property-based fuzzing.
- **Surya:** Visual architecture and inheritance graphing.

### Run the Audit

```bash
# Build the auditor image
docker build -t auditor .

# Create and run the tester container
docker create -it --name tester -v "$(pwd):/workspace/LotterySystem" auditor
docker start -ai tester
```

## Gas Optimization

As per the project requirements, we performed a deep gas audit using `forge test --gas-report` and also noted the suggestions given by `forge build --sizes` to identify and mitigate high-cost operations.

### Optimization 1: `immutable` Constants (Storage Read Bypass)

In the baseline `Lottery.sol`, the ticket price was initially a standard state variable. By refactoring this to an `immutable` type, we moved the data from contract storage directly into the contract's execution bytecode.

- **Before:** `uint256 public ticketPrice;` (Execution Cost: **65,632 gas**)
- **After:** `uint256 public immutable ticketPrice;` (Execution Cost: **63,535 gas**)
- **Impact:** Saves exactly **2,097 gas** per `buyTicket` call by avoiding the 2,100 gas cost of a cold storage read (`SLOAD`). Over a fully sold-out round of 256 tickets, this simple architectural choice saves users over 536,000 gas.

$$Saving \approx SLOAD(2100) - PUSH(3) = 2097 \text{ gas}$$

### Optimization 2: Bitmapped Ticket Tracking (Storage Slot Compression)

In `Lottery.sol`, the system supports exactly 256 tickets per round.

- **Traditional Approach:** Using a `mapping(uint256 => bool)` or a `bool[256]` array would require 256 separate storage slots, each costing **20,000 gas** for the first non-zero write.
- **Optimization:** We utilize a single `uint256` as a **Bitmask/Bitmap**. Each of the 256 bits represents a ticket index.
- **Impact:** This compresses the entire ticket-tracking state machine into **1 storage slot** ($1 \times 256$ bits), reducing the overall storage footprint by **99.6%** for round tracking.

### Optimization 3: Custom Errors (Bytecode Efficiency)

We utilized Solidity 0.8.4+ custom errors instead of traditional `require` strings.

- **Technical Reason:** Traditional revert strings (e.g., `require(condition, "Only the winner can claim")`) store long ASCII strings in the contract bytecode, increasing deployment and execution costs.
- **Impact:** Custom errors (e.g., `revert Lottery__NotWinner()`) use a 4-byte selector, significantly reducing the gas cost of failing transactions and overall deployment size.

## Tech Stack & Standards

- **Language:** Solidity `0.8.20`
- **Libraries:** OpenZeppelin `Ownable` and `ReentrancyGuard`
- **Oracle:** Chainlink VRF v2 & Chainlink Automation
- **Documentation:** Strict **NatSpec** compliance on all `public` / `external` functions
- **Frontend:** Next.js, TypeScript, Wagmi + Viem for Web3, Tailwind CSS

## Known Issues & Architectural Limitations

- **Single-Round Lifecycle:** The `Lottery.sol` contract is intentionally designed for single-round execution to maximize gas efficiency and strictly satisfy the rubric's manual Commit-Reveal parameter. (The experimental `LotteryEX.sol` contains multi-round automation).
- **Strict Capacity Limits:** To achieve 99.6% storage compression via a single `uint256 ticketBitmap`, the lottery is strictly capped at exactly 256 tickets per round.
- **Residual Trust:** Because it relies on a manual Commit-Reveal scheme (per project requirements), the contract assumes the owner will not lose the secret off-chain prior to the reveal phase.

**Veritas:** _Vires in Numeris_ (Strength in Numbers).
