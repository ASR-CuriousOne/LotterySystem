# Veritas

**Veritas** is a multi-tiered, provably fair decentralized lottery system built for the Ethereum blockchain. Moving beyond basic commit-reveal schemes, we implements autonomous, oracle-verified raffle logic using Chainlink VRF and Automation.

> **Team Mission:** 10 SPI fr.

## The Team

| Name                       | Roll Number | Role                        |
| :------------------------- | :---------- | :-------------------------- |
| **Arnav Kumar**            | 240001013   | Lead Backend & Architect    |
| **Aryaman Awanish Tiwari** | 240001014   | Stress Testing & Invariants |
| **Ayush Singh Rana**       | 240001015   | Security Audit & Exploits   |
| **Hrishabh Mittal**        | 240001035   | Fuzzing & Property Testing  |
| **Prabandham Sriniketan**  | 240001052   | Statistical Analysis & Math |
| **Yash Arya Saxena**       | 240001081   | Frontend & DApp Integration |

## System Architecture

The project is structured into three progressive iterations of lottery logic:

1.  **Lottery.sol** is the baseline implementation using a **Commit-Reveal** scheme to generate pseudo-randomness without external oracles.
2.  **LotteryVRF.sol** is an upgraded version utilizing **Chainlink VRF** to prevent miner manipulation and MEV attacks.
3.  **LotteryEX.sol** is our **"extended"** architecture. It is fully autonomous, utilizing **Chainlink Automation (Keepers)** to trigger draws, bitmapped ticket tracking for gas efficiency, and a **Pull-Over-Push** vault for secure prize claims.

## Quick Start (Foundry)

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

* **Before:** `uint256 public ticketPrice;` (Required an `SLOAD` operation).
* **After:** `uint256 public immutable ticketPrice;` (Uses a `PUSH` operation).
* **Impact:** Saves approximately **2,097 gas** per `buyTicket` call by avoiding the **2,100 gas** cost of a cold storage read.

$$Saving \approx SLOAD(2100) - PUSH(3) = 2097 \text{ gas}$$

### Optimization 2: Bitmapped Ticket Tracking (Storage Slot Compression)
In `LotteryEX.sol`, the system supports 256 tickets per round.
* **Traditional Approach:** Using a `mapping(uint256 => bool)` or a `bool[256]` array would require 256 separate storage slots, each costing **20,000 gas** for the first non-zero write.
* **Optimization:** We utilize a single `uint256` as a **Bitmask/Bitmap**. Each of the 256 bits represents a ticket index.
* **Impact:** This compresses the entire ticket-tracking state machine into **1 storage slot** ($1 \times 256$ bits), reducing the overall storage footprint by **99.6%** for round tracking.

### Optimization 3: Custom Errors (Bytecode Efficiency)
We utilized Solidity 0.8.4+ custom errors instead of traditional `require` strings.
* **Technical Reason:** Traditional revert strings (e.g., `require(condition, "Only the winner can claim")`) store long ASCII strings in the contract bytecode, increasing deployment and execution costs.
* **Impact:** Custom errors (e.g., `revert Lottery__NotWinner()`) use a 4-byte selector, significantly reducing the gas cost of failing transactions and overall deployment size.

## Tech Stack & Standards

- **Language:** Solidity 0.8.20.
- **Libraries:** OpenZeppelin `Ownable` and `ReentrancyGuard`.
- **Oracle:** Chainlink VRF v2 & Chainlink Automation.
- **Documentation:** Strict **NatSpec** compliance on all public/external functions.
- **Frontend:** React + Ethers.js + MetaMask Integration.

**Veritas:** _Vires in Numeris_ (Strength in Numbers).
