# Raw Test Logs

The raw output of the test runs that [`test-reliability-hardening.md`](../test-reliability-hardening.md) and the two earlier reports cite. They are in bats' TAP format. Only machine-specific paths (working directory, per-test temporary directories, home directory) were replaced with `<scratch>`, `<tmp>` and `<home>`. Test names, order, counts and exit codes are unchanged.

## How to read them

- `ok N name` is a pass, `not ok N name` is a failure, and `# skip` is an intended skip. The last line, `bats-exit=N`, is bats' exit code (0 means everything passed).
- `first-run-...` files are **failures I kept on purpose**. The same folder holds the later record in which the same tests pass after the cause was fixed.
- `new-...-against-old-...` files are runs of the new tests against the **pre-fix code**. They are supposed to fail, and they are the evidence that the new tests actually tell the change apart.
- `before-fix/` and `after-fix/` compare before and after under the same conditions.

## How they were produced

1. **Frozen copy.** I copied the code under test to a temporary folder and ran it from that copy. bash reads a running script line by line, so editing the original during a run makes the results unreliable.
2. **Real CLIs blocked.** I ran with a PATH that cannot reach the real `agy`, `claude` or `codex`.
   `PATH=<tripwire shim directory>:<rg link directory>:/usr/bin:/bin:/usr/sbin:/sbin`
   A shim called by one of those names records the call and refuses with exit code 97. The record taken after all runs finished is [`tripwire-log.txt`](./tripwire-log.txt). It holds only one line that predates this series (`agy models`). The opt-in checks (`optin-*`) ran with a fake `agy` (it only prints a list) on the PATH instead of the real one.
3. **Split runs.** The slow `validate_docs.bats` was split into 4 shards by alternating tests, and the other files ran in groups at the same time. The number in a shard file's name is its shard.
4. **Command shape.** `bats --tap <file>`, some filtered with `-f <regex>`.

What the logs do not contain: the output of git operations such as the merges. Also, some files (`against-old`, `optin-*`, `default-run-skips`, `pipe-safety-7-of-7`, `doc-garden-cap-tests`, `integration-contract-27-of-27`, `genuine-evidence-gate-tests-after-fixture-fix`, `new-registry-tests`, `default-reviewer-dependent-tests-22-of-22`) are re-runs, with the same command on the same frozen copy, of comparisons whose output had only been shown in the terminal at the time, so their run time differs. The results are the same as the output at the time.

## File list

### `00-integration-contract/`

| File | What it shows |
|---|---|
| `integration-contract-24-of-24.tap` | The 24 integration contract tests for the adversarial review rule and the approval gate pass |

### `01-sigpipe-and-real-cli/`

| File | What it shows |
|---|---|
| `before-fix/load-probe-strict-validation-6-of-6.txt` | Old scripts, with 10 busy loops running, strict validation of a new scaffold 6 times: all 6 pass (the random race did not reproduce) |
| `before-fix/empty-graph-small-listing.txt` | Before the fix: 1.6 KB tracked-file listing, reports the empty shadow graph and exits 1 |
| `before-fix/empty-graph-large-listing.txt` | Before the fix: same repository state with a 243 KB listing, reports nothing and exits 0 |
| `before-fix/new-pipe-safety-tests-against-old-scripts.tap` | The 7 new `pipe_safety` tests run against the old scripts: 1 passes (a control experiment), 6 fail |
| `before-fix/new-doc-garden-test-against-old-scripts.tap` | The new doc_garden large-list test run against the old scripts: the existing test passes, the new test fails |
| `after-fix/empty-graph-small-listing.txt`, `after-fix/empty-graph-large-listing.txt` | After the fix: both sizes report the empty graph and exit 1 |
| `after-fix/pipe-safety-7-of-7.tap` | The 7 new `pipe_safety` tests pass |
| `after-fix/doc-garden-cap-tests.tap` | The 2 doc_garden changed-path cap tests pass (including the large one) |
| `after-fix/default-run-skips-the-live-agy-check.tap` | In the default run the live agy catalog comparison is a `# skip` and the static check passes |
| `after-fix/optin-live-agy-check-complete-mock-catalog.tap` | The opt-in run (`CODEGUIDE_LIVE_AGY_CATALOG=1`) against a fake catalog that has every model: passes |
| `after-fix/optin-live-agy-check-incomplete-mock-catalog.tap` | The same opt-in run against a fake catalog missing one registered model: fails (the check really works) |
| `after-fix/full-suite/` | The full suite after the fix, in 6 groups. 857 ok of 859 (1 of them a skip); the 2 failures are baseline `validate_docs` failures that predate the fix (shard 1) |

### `02-hash-binding/`

| File | What it shows |
|---|---|
| `new-tests-against-old-verifier.tap` | The new TC-17 to TC-21 run against the old verifier: all 5 fail |
| `integration-contract-27-of-27.tap` | The 27 integration contract tests pass after hash binding |
| `first-run-fixture-defect-9-failures.tap` | **The first run**: 9 gate tests that use a genuine review failed with "the plan changed after the review". The cause was the test fixture overwriting the reviewed plan |
| `genuine-evidence-gate-tests-after-fixture-fix.tap` | After the fixture fix, the 24 gate and evidence tests that use genuine evidence pass |
| `wrapper-driven-suites-233-of-233.tap` | The 233 tests of the suites that use the wrapper (external_review, run_codeguide, doc_garden, integration, shadow_v2) pass |
| `on-merged-main-full-suite/` | The full suite on the main that holds the registry update and the SIGPIPE fix, in 6 groups. 863 ok of 865 (1 of them a skip); the 2 failures are the same baseline failures |

### `03-model-registry/`

| File | What it shows |
|---|---|
| `new-tests-against-old-registry.tap` | The new and extended registry tests run against the old registry: 1 existing test passes, 3 fail |
| `new-registry-tests.tap` | The same tests pass against the new registry (5 tests, including the default-reviewer tests) |
| `external-review-suite-before-default-change-75-of-75.tap` | The 75 `external_review` tests pass with the new models registered, before the default reviewer was changed |
| `first-run-after-default-change-232-of-233.tap` | **Right after the default reviewer was changed**: 1 of 233 failed. It is a test that names Terra as the evaluator, and the evaluator must be in the default reviewer set |
| `default-reviewer-dependent-tests-22-of-22.tap` | After renaming that test to the new default, the 22 tests that depend on the default pass |
| `gate-tests-32-of-32.tap` | The 32 gate and evidence tests pass with the same change |

### `04-merged-main/`

| File | What it shows |
|---|---|
| `after-registry-and-sigpipe-merge-external_review-and-pipe_safety.tap` | After merging the registry and SIGPIPE fixes into main: 84 ok (1 of them an intended skip) |
| `after-registry-and-sigpipe-merge-other-suites.tap` | The other suites on the same main: 190 pass |
| `after-registry-and-sigpipe-merge-gate-tests.tap` | The gate and evidence tests on the same main: 31 pass |
| `after-all-merges-packaging-integration-pipe_safety.tap` | After all merges: 46 packaging, integration and `pipe_safety` tests pass |
| `after-all-merges-front_cli-and-fast-suites.tap` | After all merges: 84 `front_cli` and fast-suite tests pass |

### Other

| File | What it shows |
|---|---|
| `tripwire-log.txt` | The calls recorded by the real-CLI shims after the runs above finished: one line (`agy models`, from before this series) |

## Limits

- These logs record single runs, not statistical repetition. The race that failed at random under load did not reproduce this time (`before-fix/load-probe-...`).
- The 2 baseline failures remain as they were in `validate_docs` shard 1 of the `full-suite` logs. This work neither fixed nor worsened them, and their cause was not investigated.
