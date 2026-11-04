# Echidna fuzzing targets for part2
#
# Usage:
#   make echidna   # run the Echidna fuzzer on the ABDK template
#   make           # same as `make echidna` (default target)
#
# Requirements:
#   - echidna must be installed and on PATH (https://github.com/crytic/echidna)
#
# The command below fuzzes `EchidnaTemplate` in src/abdk/Template.sol using the
# settings from src/abdk/config.yaml (test limits, seq len, contract deployer, etc).

.PHONY: echidna
echidna-abdk:
	echidna src/abdk/Template.sol --contract EchidnaTemplate --config src/abdk/config.yaml

.DEFAULT_GOAL := echidna

echidna-staker:
	echidna src/staker/contracts/Template.sol --contract EchidnaTemplate --config src/staker/config.yaml