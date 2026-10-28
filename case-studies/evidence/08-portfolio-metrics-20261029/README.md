# Portfolio Metrics Evidence — 2026-10-29 KST

Original outputs from the current local checkout. JSON timestamps are UTC (`2026-10-28T15:...Z`), which is 2026-10-29 in KST.

## Commands and Files

| Experiment | Command shape | Evidence |
| --- | --- | --- |
| Fast gate, repeated 5 times | `./scripts/check_all.sh <project> --suite fast --skip-pytest --metrics-out <file>` | `fast-run-1.log` to `fast-run-5.log`, `fast-metrics.jsonl` |
| 20 evidence attacks | `bats --filter '^external-review gate rejects tampered, missing, mismatched or hand-written evidence$' tests/validate_docs.bats` | `tamper-20.tap` |
| Invalid waiver variants | `bats --filter 'waiver' tests/validate_docs.bats` | `waiver.tap` |
| 8,000 IDs and 1,500 tracked files, repeated 5 times | `bats --filter '<three large-input test names>' tests/pipe_safety.bats` | `large-pipe-run-1.tap` to `large-pipe-run-5.tap` |
| 1,500 changed paths, repeated 5 times | `bats --filter 'doc_garden caps a large changed-file list without a broken-pipe failure' tests/doc_garden.bats` | `large-garden-run-1.tap` to `large-garden-run-5.tap` |

The waiver selection runs five enclosing tests. Their fixtures exercise eight invalid variants: one missing verified decision, one free-text waiver, three invalid waiver fields, two path or symlink escapes, and one invented strict gate. The large-input selection runs four tests per repetition, for 20 test executions total.

## Integrity and Limits

- Only machine-specific absolute project and temporary paths were replaced with `<project>` and `<tmp>`. Test names, order, counts, metrics, and results are unchanged.
- TAP records the result of each enclosing Bats test. The source test is the authoritative enumeration of variants inside that test.
- This folder does not claim a complete run of the 867-test Bats suite. It records only the experiments listed above.
- Whole-run timings are whole-second wall measurements on one machine and are not a cross-machine benchmark.
