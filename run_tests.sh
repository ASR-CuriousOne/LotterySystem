#!/bin/bash
set -e

echo "Starting automated build, test, and audit sequence..."
target_repo_dir="/workspace/LotterySystem"
cd "$target_repo_dir"
mkdir -p reports

echo "===================================================================================="
echo "=========================== Phase 1: Foundry Operations ============================"
echo "===================================================================================="

git config --global --add safe.directory '*'
forge install
forge remappings > remappings.txt

echo "Formatting contracts..."
forge fmt

echo "Building contracts..."
forge build --sizes > "reports/foundry/contract-sizes.txt" 2>&1

echo "Running tests and generating gas report..."
forge test -vvv --gas-report > "reports/foundry/gas-report.txt" 2>&1

echo "Running coverage analysis..."
forge coverage > "reports/foundry/coverage-report.txt" 2>&1

echo "Executing deployment dry-runs..."
if [ -f "script/Deploy.s.sol" ]; then
    echo "Running script..."
    forge script "script/Deploy.s.sol" -vvv > "reports/foundry/deploy-script.txt" 2>&1
fi

echo "===================================================================================="
echo "============================= Phase 2: Security Audits ============================="
echo "===================================================================================="

echo "Running Slither (Static Analysis)"
slither . --print human-summary > "reports/slither/audit.txt" 2>&1 || true

echo "Running Surya (Architecture & Graphs)"
ALL_CONTRACTS=$(find src -name "*.sol")
surya describe $ALL_CONTRACTS --no-color > "reports/surya/contract-description.txt" 2>&1 || true
surya inheritance $ALL_CONTRACTS > "reports/surya/inheritance-graph.dot" 2>&1 || true

echo "Running Mythril (Symbolic Execution)"
if [ -f "src/Lottery.sol" ]; then
    echo "Analyzing Base Lottery..."
    myth analyze "src/Lottery.sol" --solc-json mythril_solc.json --max-depth 100 > "reports/mythril/base.txt" 2>&1 || true
fi
if [ -f "src/LotteryVRF.sol" ]; then
    echo "Analyzing Lottery VRF..."
    myth analyze "src/LotteryVRF.sol" --solc-json mythril_solc.json --max-depth 100 > "reports/mythril/vrf.txt" 2>&1 || true
fi

echo "Running Echidna (Fuzzing)"
if [ -f "test/echidna/EchidnaLottery.t.sol" ]; then
    echo "Fuzzing Base Lottery..."
    echidna "test/echidna/EchidnaLottery.t.sol" --contract "EchidnaLottery" --config echidna.yaml --format text > "reports/echidna/base.txt" 2>&1 || true
fi
if [ -f "test/echidna/EchidnaLotteryVRF.t.sol" ]; then
    echo "Fuzzing Lottery VRF..."
    echidna "test/echidna/EchidnaLotteryVRF.t.sol" --contract "EchidnaLotteryVRF" --config echidna.yaml --format text > "reports/echidna/vrf.txt" 2>&1 || true
fi
if [ -f "test/echidna/EchidnaLotteryEX.t.sol" ]; then
    echo "Fuzzing Extended Lottery..."
    echidna "test/echidna/EchidnaLotteryEX.t.sol" --contract "EchidnaLotteryEX" --config echidna.yaml --format text > "reports/echidna/ex.txt" 2>&1 || true
fi

echo "Running cleanup..."
forge clean
rm -rf crytic-export
rm -f remappings.txt

echo "===================================================================================="
echo "================= Sequence Complete. Reports generated in /reports ================="
echo "===================================================================================="
echo "========================== Omitted Tools & Justifications =========================="
echo "* SmartBugs & Securify: These tools rely on Docker-in-Docker (DinD) architectures =="
echo "  , which compromise the security and stability of an isolated local container.   =="
echo "* Manticore: Its custom Python EVM emulator struggles to parse modern Solidity.   =="
echo "  (0.8+) panic opcodes and recent network forks, causing deployment exceptions.   =="
echo "* Tenderly CLI: It is a cloud-based platform that requires API credentials and.   =="
echo "  live network forks to simulate transactions.                                    =="
echo "* Forta Agent: It is a runtime monitoring network designed for live, deployed     =="
echo "  contracts, not local static/symbolic analysis.                                  =="
echo "===================================================================================="