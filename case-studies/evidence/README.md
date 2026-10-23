# Raw Test Logs

Raw bats TAP output for the test runs behind the three reports in the parent folder. There are two kinds of log:

- **Original run outputs**: folders `00` to `04`, folder `07` and [`tripwire-log.txt`](./tripwire-log.txt). They back the newest report, [`test-reliability-hardening.md`](../test-reliability-hardening.md), and, for the integration contract, one run of the second report. Folder `07` backs the later fix of the two baseline test failures.
- **Regenerated logs**: folders `05` and `06` and [`tripwire-log-regenerated.txt`](./tripwire-log-regenerated.txt). They back the two earlier reports. The original runs of those reports were not saved, so their key runs were re-run later from the old commits. Each regenerated file says so on its second line.

[Coverage of the three reports](#coverage-of-the-three-reports) lists which claim is backed by which log and which claims have no log. Only machine-specific paths (working directory, per-test temporary directories, home directory) were replaced with `<scratch>`, `<tmp>` and `<home>`. Test names, order, counts and exit codes are unchanged.

## How to read them

- `ok N name` is a pass, `not ok N name` is a failure, and `# skip` is an intended skip. The last line, `bats-exit=N`, is bats' exit code (0 means everything passed).
- `first-run-...` files are **failures I kept on purpose**. The same folder holds the later record in which the same tests pass after the cause was fixed.
- `new-...-against-old-...` files and the `before-fix/` files of folders `05` and `06` are runs of the new tests against the **pre-fix code**. They are supposed to fail, and they are the evidence that the new tests actually tell the change apart.
- `before-fix/` and `after-fix/` compare before and after under the same conditions.
- The two `# REGENERATED LOG` comment lines after the plan line of every file in folders `05` and `06` name the tree and the command that produced it. Those files are not the output of the original runs.

## How they were produced

1. **Frozen copy.** I copied the code under test to a temporary folder and ran it from that copy. bash reads a running script line by line, so editing the original during a run makes the results unreliable.
2. **Real CLIs blocked.** I ran with a PATH that cannot reach the real `agy`, `claude` or `codex`.
   `PATH=<tripwire shim directory>:<rg link directory>:/usr/bin:/bin:/usr/sbin:/sbin`
   A shim called by one of those names records the call and refuses with exit code 97. The record taken after all runs finished is [`tripwire-log.txt`](./tripwire-log.txt). It holds only one line that predates this series (`agy models`). The opt-in checks (`optin-*`) ran with a fake `agy` (it only prints a list) on the PATH instead of the real one.
3. **Split runs.** The slow `validate_docs.bats` was split into 4 shards by alternating tests, and the other files ran in groups at the same time. The number in a shard file's name is its shard.
4. **Command shape.** `bats --tap <file>`, some filtered with `-f <regex>`.
5. **Regenerated runs (folders `05` and `06`).** On 2026-10-23 I exported four old skill commits with `git archive` (`7fc71f8`, `13a1597`, `6476e2d`, `2ecf622`) into frozen copies. An "after" run uses the fixing commit itself. A "before" run uses the scripts of the commit before the fix together with the tests of the fixing commit, so the only thing missing is the fix. These runs used a fresh set of tripwire shims with their own log and at most two concurrent bats processes, because the old scripts still carry the SIGPIPE race that heavy load can trigger.

What the logs do not contain: the output of git operations such as the merges. Also, some files (`against-old`, `optin-*`, `default-run-skips`, `pipe-safety-7-of-7`, `doc-garden-cap-tests`, `integration-contract-27-of-27`, `genuine-evidence-gate-tests-after-fixture-fix`, `new-registry-tests`, `default-reviewer-dependent-tests-22-of-22`) are re-runs, with the same command on the same frozen copy, of comparisons whose output had only been shown in the terminal at the time, so their run time differs. The results are the same as the output at the time.

## Coverage of the three reports

| Report | Claim | Log |
|---|---|---|
| [Test reliability hardening](../test-reliability-hardening.md) (newest) | Every count in the report | Original runs, folders `00` to `04` |
| [Adversarial rule x approval gate integration](../adversarial-gate-integration.html) | Integration suite 24 of 24, three runs | One original run in `00-integration-contract/`; three regenerated runs in `06-adversarial-integration-regenerated/after-fix/` |
| | The pre-fix verifier was stricter than the wrapper (the one mismatch) | Regenerated: 10 of the 24 tests fail on the pre-fix verifier, `06-.../before-fix/` |
| | `run_codeguide.bats` and `external_review.bats`: 115 of 116, the one failure being the real-agy test stopped by the tripwire | Regenerated: 115 of 116 with the same failure, plus [`tripwire-log-regenerated.txt`](./tripwire-log-regenerated.txt) |
| | Other suites: 272 of 272 (14 files, the file list was not recorded) | Regenerated as a wider run: all 22 other files, 423 of 423 |
| | `validate_docs.bats`: 285 of 287 | **No log.** Not regenerated |
| [External review approval gate hardening](../external-review-gate-hardening.html) | `run_codeguide.bats` 43 of 43, 12 of them new | Regenerated: 43 of 43; the same file on the old scripts gives 35 pass and 8 fail, `05-gate-hardening-regenerated/` |
| | The new tests fail on the old scripts (the five audited defects) | Regenerated: 27 of 31 gate tests fail on the old scripts |
| | Gate target tests 33 of 33 | Regenerated with a different selection: the 31 `validate_docs` tests the commit added or rewrote, 31 of 31. The original selection was not recorded |
| | Shadow reader audit 8 of 8 | Regenerated: 8 of 8 |
| | `validate_docs.bats` 265 pass and 22 failed (20 pass on rerun); the 13-file, 235-test run; the advisory output compared over a frozen docs corpus; the repeated strict-scaffold runs; the bash 3.2.57 run | **No log.** Not regenerated |

Why some claims were not regenerated: `validate_docs.bats` takes hours, and the old scripts carry the SIGPIPE race that load triggers, so a run on the old tree would not be stable. The later full-suite logs (`01-sigpipe-and-real-cli/after-fix/full-suite/` and `02-hash-binding/on-merged-main-full-suite/`) cover `validate_docs.bats` on newer trees. The other comparisons need inputs of that day (a frozen docs corpus, a specific shell) that are not in the repository. The full `validate_docs.bats` of the current tree, after the two stale tests were fixed, is in `07-baseline-test-fixes/` (287 of 287).

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

### `05-gate-hardening-regenerated/` (regenerated, report: external review approval gate hardening)

| File | What it shows |
|---|---|
| `after-fix/run_codeguide-43-of-43.tap` | `run_codeguide.bats` at `13a1597`: all 43 tests pass |
| `before-fix/run_codeguide-tests-against-old-scripts.tap` | The same 43 tests against the scripts of `7fc71f8`: 35 pass, 8 fail. The 8 are the gate stopping before docs mutation, blocking closing, blocking reopening, proceeding with complete evidence, and four ORCH-preservation tests. The other 4 new tests pin behavior that already held, so they pass on both |
| `after-fix/validate_docs-gate-tests-31-of-31.tap` | The 31 `validate_docs` tests that `13a1597` added or rewrote: all pass |
| `before-fix/validate_docs-gate-tests-against-old-scripts.tap` | The same 31 against the old scripts: 4 pass, 27 fail. The 4 that pass pin behavior the fix keeps: complete wrapper evidence, the retry-response set, done tasks not re-measured, and the historical verdict reading |
| `after-fix/shadow_reader_audit-8-of-8.tap` | `shadow_reader_audit.bats` at `13a1597`: all 8 pass |

### `06-adversarial-integration-regenerated/` (regenerated, report: adversarial rule x approval gate integration)

| File | What it shows |
|---|---|
| `before-fix/integration-tests-against-pre-fix-verifier.tap` | The 24 integration tests against the verifier of `6476e2d`: 14 pass, 10 fail. All 10 trace to one mismatch: the wrapper accepts an adversarial accept whose objection, counterproposal and rebuttal are present but empty, and the pre-fix verifier rejects it (the PARITY-01 failure line says so). TC-01 and PARITY-01 test it directly; TC-07, TC-08, TC-09, TC-10, KL-1 and KL-2 fail inside the shared fixture `adv_empty_base`; TC-12 and TC-13 build on the same response |
| `after-fix/integration-suite-24-of-24-run1.tap`, `-run2.tap`, `-run3.tap` | The 24 integration tests at `2ecf622`, three runs: all pass each time |
| `after-fix/run_codeguide-and-external_review-115-of-116.tap` | `run_codeguide.bats` and `external_review.bats` at `2ecf622`: 115 of 116 pass. The one failure is `bundled agy routes use catalog cli_model values`, which at that commit ran `agy models` whenever agy was on PATH; the tripwire shim refused it |
| `after-fix/other-suites-non-shadow-227-of-227.tap`, `after-fix/other-suites-shadow-196-of-196.tap` | Every other suite at `2ecf622` (22 files, 423 tests): all pass |

### `07-baseline-test-fixes/` (original runs on 2026-10-23, later than the reports above)

| File | What it shows |
|---|---|
| `before-fix/two-tests-on-main.tap` | The two baseline tests run alone on the pushed main: both fail. Strict validation of a done task with empty close-record fields fails the terminal close-record gate, and the JSON issue id of the empty `disposition` is now `check_close_field_block_non_empty` instead of `check_field_non_empty` |
| `first-run-lineage-fix-incomplete-1-failure.tap` | **The first attempt at the fix, kept on purpose**: the JSON id test passes, the lineage test still fails. Filling `objective`, `acceptance_criteria` and `outcome` was not enough, because the task-index row summary projects from the stored outcome and no longer matched; the test now rebuilds the index |
| `after-fix/two-tests-fixed-2-of-2.tap` | The same two tests after the fix: both pass |
| `after-fix/validate_docs-full-shard-1-of-4.tap` to `-4-of-4.tap` | The whole `validate_docs.bats` of the fixed tree, 287 tests in four parallel shards (72, 72, 72, 71): all pass. Four shards at once is the load that used to trigger the SIGPIPE race, and no random failure appeared |

### Other

| File | What it shows |
|---|---|
| `tripwire-log.txt` | The calls recorded by the real-CLI shims after the runs of folders `00` to `04` finished: one line (`agy models`, from before this series) |
| `tripwire-log-regenerated.txt` | The calls recorded by the shims during the regenerated runs of folders `05` and `06` and the runs of folder `07`: one line, `agy models`, the old real-agy test of `2ecf622` stopped by the shim. Nothing else reached a real CLI |

## Limits

- These logs record single runs, not statistical repetition. The race that failed at random under load did not reproduce this time (`before-fix/load-probe-...`).
- The 2 baseline failures stay visible in `validate_docs` shard 1 of the `full-suite` logs of folders `01` and `02`, because those logs were taken before the tests were fixed. Their cause (two stale test expectations left by the terminal close-record gate) and the fix are in `07-baseline-test-fixes/`.
- The files in folders `05` and `06` are regenerated, not the original outputs, which were not saved. They come from the same commits and commands as the reports describe, so the counts match where the selection is the same, and the coverage table lists the differences. Reports measured their "before" numbers on the working tree before the fix was committed, so a regenerated "before" run agrees with them only as far as the commit equals that tree.
