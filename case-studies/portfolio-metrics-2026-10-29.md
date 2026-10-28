# Portfolio Validation Metrics

Measured on 2026-10-29 KST against the current local checkout.

## Outcome

| Experiment | Result | Timing |
| --- | ---: | ---: |
| Fast quality gate, 50 tests x 5 runs | 250/250 passed; 0 observed flakes | median 79s; max 80s |
| Tampered evidence and invalid waivers | 28/28 rejected | targeted runs |
| Large-input scenarios, 4 tests x 5 runs | 20/20 passed | 13s per run |

The large-input runs covered 8,000 registry IDs, 1,500 tracked files with a listing larger than 64 KiB, and 1,500 changed paths capped to 10 displayed paths plus `(+1490 more)`.

## Method

The fast experiment ran `scripts/check_all.sh --suite fast --skip-pytest` five times. Each run executed the same 50 Bats tests plus strict documentation validation, the English-document policy, and packaging hygiene. Stage metrics were appended to JSONL.

The approval-gate experiment selected the test that exercises 20 tampered, missing, mismatched, or hand-written evidence variants and the five waiver tests. The waiver fixtures contain eight invalid variants in total: missing verified decision, free text, three invalid fields, two path or symlink escapes, and an invented strict gate.

The large-input experiment repeated three pipe-safety tests and one doc-garden cap test five times. All commands and original outputs are listed in the [evidence manifest](./evidence/08-portfolio-metrics-20261029/README.md).

## Limits

- The complete Bats suite contains 867 tests, but this experiment did not run that complete suite.
- Zero observed flakes in five runs is not proof that flakiness is impossible.
- The timing uses whole-second wall and stage measurements on one local machine; it is not a cross-machine benchmark.
- These tests demonstrate contract enforcement and bounded-input behavior, not business impact or developer-productivity improvement.
- The source test remains the authoritative definition of each adversarial variant; the TAP output records the enclosing test result.
