# AGENTS.md

## Layout

- Six independent Foundry/Echidna workshop projects in `part1/`..`part6/`. There is no root workspace, manifest, or build; always `cd` into the part directory first.
- Each part has its own `foundry.toml`, vendored `lib/`, and `.github/workflows/test.yml`.
- `part1`-`part4` keep sources under `src/`; `part5`-`part6` use Primitive Finance sources under `contracts/` pinned to solc 0.8.6.
- The working tree is mid-migration from Hardhat to Foundry: old `hardhat.config.*`, `package*.json`, and legacy source trees are deleted, while most Foundry files are still untracked. Stage only files relevant to your task; do not restore the deleted Hardhat files or run `git add -A` blindly.

## Verification commands

Echidna is not vendored or installed here. Makefiles invoke `echidna`; older docs say `echidna-test` for the same binary.

- part1: `cd part1 && forge test`
- part2: `cd part2 && forge build && forge test --match-contract ABDKMathMulTest`
- part3: `cd part3 && forge test --match-path test/UniswapV2Pair.t.sol`
- part4: `cd part4 && make echidna`
- part5: `cd part5 && echidna . --contract LibraryMathEchidna --corpus-dir corpus --test-mode assertion --format text`
- part6: `cd part6 && unzip -n corpus.zip && echidna contracts/crytic/EchidnaE2E.sol --contract EchidnaE2E --config contracts/crytic/E2ECore.yaml`

`part2`'s bare `make`/`make echidna` target has no recipe; use `make -C part2 echidna-abdk` or `make -C part2 echidna-staker`. `part3`/`part4` also expose `make -C partN echidna`.

## Echidna targets

- part2: `EchidnaTemplate` with `src/abdk/config.yaml`; `EchidnaTemplate` with `src/staker/config.yaml`.
- part3: `EchidnaTest` with `src/contracts/crytic/config.yaml`.
- part4: `EchidnaUniV2Tester` with `src/contracts/crytic/config.yaml`. The README's `contracts/...` paths are stale.
- part6: `EchidnaE2E` with `contracts/crytic/E2ECore.yaml`, seeded by `contracts/crytic/init.json`. If the target code changes, regenerate addresses via Etheno/Ganache as described in `part6/README.md`; the addresses hardcoded in `EchidnaE2E.sol` must match the deployment.

## Known traps

- Full `forge test` is only green in part1. In parts 2 and 3, Forge also treats Echidna `test*` methods under `src/` as tests; use the focused commands above.
- In part3/part4, Uni-V2 sources are `^0.6.x` while forge-std needs `>=0.8.13`. Foundry tests must use 0.8 interfaces plus `deployCode(...)`, as `part3/test/UniswapV2Pair.t.sol` does; do not import the 0.6 contracts directly.
- part4's `foundry.toml` sets `src = "contracts"`, but sources are under `src/contracts`. `forge build`/`forge test` silently report "Nothing to compile"; fix it to `src = "src"` before relying on Forge, or use `make echidna`.
- part5 currently fails to compile: `contracts/echidna/LibraryMathEchidna.sol` declares `liquidity0` and `liquidity1` twice around lines 25-33.
- part6 has no Forge test suite; `forge test` fails on helper `test*`/`invariantOf` functions under `contracts/`. Use Echidna.
- Each part's CI runs `forge fmt --check`, `forge build --sizes`, and `forge test -vvv`; CI does not run Echidna. Baseline fmt checks already fail in parts 2, 5, and 6, so avoid repo-wide reformatting and unrelated diffs.
- `out/`, `cache/`, `corpus/`, and `crytic-export/` are generated/ignored; `part6/corpus.zip` is the tracked seed. Do not edit vendored code in `lib/` (forge-std, plus OpenZeppelin in part2).

## Custom Instructions

- Don't solve my security exercises for me
- Leave my original comments when making changes