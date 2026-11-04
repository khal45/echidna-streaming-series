# Echidna fuzzing target for part3 (Uniswap V2 invariants)
#
# Usage:
#   make echidna   # run the Echidna fuzzer on the Uniswap V2 test contract
#   make           # same as `make echidna` (default target)
#
# Requirements:
#   - echidna must be installed and on PATH (https://github.com/crytic/echidna)
#
# The command below fuzzes `EchidnaTest` (defined in
# src/contracts/crytic/EchidnaTest.sol) using the settings from
# src/contracts/crytic/config.yaml (assertion mode, seq length, test limit, ...).
#
# Notes:
#   - The fuzzer stores/loads its corpus in the `corpus/` directory
#     (corpusDir in config.yaml); delete it to start a fresh campaign.
#   - A coverage report is written to `coverage/` on completion.

.PHONY: echidna
echidna:
	echidna src/contracts/crytic/EchidnaTest.sol --contract EchidnaTest --config src/contracts/crytic/config.yaml

.DEFAULT_GOAL := echidna
