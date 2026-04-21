#!/bin/bash
set -e

echo "Starting automated build, test, and audit sequence..."
target_repo_dir="/workspace/LotterySystem"
cd "$target_repo_dir"


echo "============================="
echo " Phase 1: Foundry Operations "
echo "============================="

git config --global --add safe.directory '*'

forge install

echo "Generating remappings for external tools..."
forge remappings > remappings.txt

echo "Formatting contracts..."
forge fmt

echo "Building contracts..."
forge build --sizes

echo "Running tests and generating gas report..."
forge test -vvv --gas-report

echo "Running coverage analysis..."
forge coverage

echo "Executing scripts..."
if [ -d "script" ]; then
    find script -name "*.s.sol" | while read -r script_file; do
        echo "Running script: $script_file"
        forge script "$script_file" -vvv
    done
else
    echo "No script directory found. Skipping."
fi

echo "=========================="
echo " Phase 2: Security Audits "
echo "=========================="

TIMEOUT=60

echo "Running Slither (Static Analysis)"
slither . || true

echo "Running Surya (Architecture & Graphs)"
ALL_CONTRACTS=$(find src -name "*.sol")
surya describe $ALL_CONTRACTS || true
surya inheritance $ALL_CONTRACTS || true

echo "Running Mythril (Symbolic Execution)"
cat <<EOF > mythril_solc.json
{
  "remappings": [
    "openzeppelin-contracts/=lib/openzeppelin-contracts/",
    "chainlink-brownie-contracts/=lib/chainlink-brownie-contracts/",
    "forge-std/=lib/forge-std/src/"
  ],
  "optimizer": {
    "enabled": true,
    "runs": 200
  }
}
EOF
find src -name "*.sol" | while read -r contract_file; do
    echo "Analyzing $contract_file with Mythril (Max ${TIMEOUT}s)..."
    myth analyze "$contract_file" --solc-json mythril_solc.json --execution-timeout $TIMEOUT || true
done

echo "Running Echidna (Fuzzing)"

# 1. Base Lottery
if [ -f "test/EchidnaLottery.t.sol" ]; then
    echo "Fuzzing Base Lottery (Target: EchidnaLottery).."
    echidna "test/EchidnaLottery.t.sol" --contract "EchidnaLottery"
fi

# 2. Lottery VRF
if [ -f "test/EchidnaLotteryVRF.t.sol" ]; then
    echo "Fuzzing Lottery VRF (Target: EchidnaLotteryVRF)..."
    echidna "test/EchidnaLotteryVRF.t.sol" --contract "EchidnaLotteryVRF"
fi

# 3. Lottery EX
if [ -f "test/EchidnaLotteryEX.t.sol" ]; then
    echo "Fuzzing Lottery EX (Target: EchidnaLotteryEX)..."
    echidna "test/EchidnaLotteryEX.t.sol" --contract "EchidnaLotteryEX"
fi
echo "Running cleanup..."
forge clean
rm -rf crytic-export
rm -f remappings.txt mythril_solc.json

echo "===================="
echo " Execution Complete "
echo "===================="

echo "--- Omitted Tools & Justifications ---"
echo "* SmartBugs & Securify: Omitted entirely. These tools rely on Docker-in-Docker (DinD) architectures, which compromise the security and stability of an isolated local container."
echo "* Manticore: Omitted entirely. Its custom Python EVM emulator struggles to parse modern Solidity (0.8+) panic opcodes and recent network forks, causing deployment exceptions."
echo "* Tenderly CLI: Installed for manual debugging, but bypassed in automation. It is a cloud-based platform that requires API credentials and live network forks to simulate transactions."
echo "* Forta Agent: Installed for bot development, but bypassed in automation. Forta is a runtime monitoring network designed for live, deployed contracts, not local static/symbolic analysis."
echo "======================================"
