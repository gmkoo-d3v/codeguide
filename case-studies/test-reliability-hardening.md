# Test Reliability Hardening Report

> codeguide · follow-up work on validation reliability. A point-in-time record, written as the work was done.
> Korean HTML version of the same report: [test-reliability-hardening.html](./test-reliability-hardening.html) · Raw test logs this report cites: [evidence/](./evidence/)

## Summary

I fixed the places where validation gave a wrong answer or silently skipped a check.

- Cleaned up **14 sites** where an early-closing pipe changed a result, and stopped the default test run from executing the real `agy`.
- Bound approved external reviews to the **hashes of the plan and the request**.
- Registered **17 new model routes** in the registry and changed the default OpenAI reviewer to GPT-6.1 Sol (medium).

All four pieces of work are on `main`. In the full suite on the merged main there are **no new failures, and no real external CLI was ever run.**

| Metric | Value | Raw log |
|---|---|---|
| Full suite on main with hash binding merged | 863 ok of 865 (1 of them an intended skip); the 2 failures predate this work | [on-merged-main-full-suite/](./evidence/02-hash-binding/on-merged-main-full-suite/) |
| Early-exit pipes | 14 sites fixed; 3 sites where the wrong behavior was reproduced | [01-sigpipe-and-real-cli/](./evidence/01-sigpipe-and-real-cli/) |
| New hash-binding tests | All 5 fail against the old verifier | [new-tests-against-old-verifier.tap](./evidence/02-hash-binding/new-tests-against-old-verifier.tap) |
| Real CLI executions in this series | 0 (the log holds one older `agy models` line from before the series) | [tripwire-log.txt](./evidence/tripwire-log.txt) |

## 1. Status of the four tasks

| Task | Commit in the skill repo | Key evidence |
|---|---|---|
| Model registry update | `3e8d5be` | 17 new routes; default reviewer GPT-6.1 Sol (medium). 3 new or extended tests fail against the old registry |
| SIGPIPE and real-CLI fix | `bab734f` | 3 deterministic reproductions; 6 of the 7 new tests fail against the old scripts (the 7th is a control experiment); full suite 857 ok of 859 |
| Plan and request hash binding | `1b8b860` | Integration suite 27/27; the new TC-17 to TC-21 fail 5/5 against the old verifier; wrapper-driven suites 233/233 |
| README and case-studies | `a800c38`, `f5bb978` | Packaging tests 12/12. The old classifier labeled the new folder UNKNOWN, which broke the gate |

## 2. Early-exit pipes: the most dangerous form is a silent pass

A pipe whose consumer finishes early (`grep -q`, `grep -m1`, `head -n N`) kills a still-writing producer with SIGPIPE. Under `set -o pipefail` that exit status becomes the status of the whole pipe, so **a correct answer reads as a failure.** I surveyed all 26 such pipes in the scripts and fixed 14. The rest have their status masked by `|| true`, or the producer writes a single line, so they are unaffected.

| Reproduction | Before the fix | After the fix |
|---|---|---|
| **Empty shadow-graph check** (a repository with source files but no shadow units) | With a 1.6 KB tracked-file listing: reports `shadow graph is empty`, exit 1. **With a 243 KB listing: strict validation passes without reporting anything, exit 0** | Both sizes report it and exit 1 |
| **Registry id membership check** (a unit test feeding a list of 8,000 ids) | Reports 4 ids that are in the list as "not declared" | 0 reports |
| **doc_garden resume checkpoint** (1,500 changed paths) | The script aborts under `set -e` | Exits normally and records `(+1490 more)` |

- **The silent side is worse.** A check that fails at random gets noticed. A check that is skipped, and passes, only because the repository grew is noticed by no one.
- **How I fixed it.** The membership check became a pure-bash `case` helper (`list_has_line`) that uses neither a pipe nor a temporary file. I deliberately avoided here-strings: bash 3.2 implements them with a temporary file that ignores `$TMPDIR`, which can break the validator in a sandbox. The other sites became `sed -n '1,10p'`, which reads its input to the end, and a read loop that stops at the first source path.
- **Regression guard.** A static check in `tests/pipe_safety.bats` stops this pattern from re-entering `scripts/`. The helper was compared with `grep -Fx` on 23 boundary cases (whole-line match, glob and regex characters, whitespace, an empty list, a leading dash, letter case) and gave the same answers.
- **What I could not reproduce.** The random failure of the id check under load did not reproduce this time (strict validation passed 6 of 6 under 10 busy loops). I covered that part with the large-list unit test and the static check, and I do not claim it was proven by a real load reproduction.

Raw logs: before the fix [load-probe](./evidence/01-sigpipe-and-real-cli/before-fix/load-probe-strict-validation-6-of-6.txt) · [empty graph, small listing](./evidence/01-sigpipe-and-real-cli/before-fix/empty-graph-small-listing.txt) · [empty graph, large listing](./evidence/01-sigpipe-and-real-cli/before-fix/empty-graph-large-listing.txt) · [new tests run against the old scripts](./evidence/01-sigpipe-and-real-cli/before-fix/new-pipe-safety-tests-against-old-scripts.tap); after the fix [pipe-safety 7/7](./evidence/01-sigpipe-and-real-cli/after-fix/pipe-safety-7-of-7.tap) · [full suite](./evidence/01-sigpipe-and-real-cli/after-fix/full-suite/)

## 3. Keeping the default tests from running the real agy

- The tripwire log from the earlier integration work held one line, `agy models`. One existing test (`bundled agy routes use catalog cli_model values`) ran the real `agy models` whenever `agy` was on `PATH`, and it was the only place in the whole suite that touched a real CLI.
- The static registry map check now always runs. The comparison against the live catalog runs only when `CODEGUIDE_LIVE_AGY_CATALOG=1`. The skip is recorded in the TAP output as `# skip`.
- I also verified the opt-in path itself with a mock `agy`: it passes with a catalog that has every model and fails with a catalog that is missing one registered model.
- This moves one automated check to opt-in. The default run no longer compares against the live catalog, so when models are updated a person has to turn it on once to confirm.

Raw logs: [default run skips the check](./evidence/01-sigpipe-and-real-cli/after-fix/default-run-skips-the-live-agy-check.tap) · [opt-in run, complete mock catalog](./evidence/01-sigpipe-and-real-cli/after-fix/optin-live-agy-check-complete-mock-catalog.tap) · [opt-in run, mock catalog missing a model](./evidence/01-sigpipe-and-real-cli/after-fix/optin-live-agy-check-incomplete-mock-catalog.tap)

## 4. Binding the approved review to the plan and the request

Before, the manifest held only the response hash, so editing the plan or changing the request after the review ended still let the old approval through. Now the request records `plan_sha256`, the manifest records `request_sha256` and `plan_sha256`, and the verifier recomputes them from the current files.

| ID | Rejected case | Old verifier |
|---|---|---|
| TC-17 | Plan edited after the review | Passed it |
| TC-18 | Request changed after the review | Passed it |
| TC-19 | Old manifest without hashes (a new review round is required) | Passed it |
| TC-20 | Manifest disagrees with the plan hash recorded in the request | Passed it |
| TC-21 | Plan file cannot be found | Passed it |

**The tests caught a defect in their own change.** On the first run, 9 gate tests that use a genuine review failed with "the plan changed after the review". It was not a verifier defect. The test fixture was overwriting the plan the review had read with different content, and the hash binding reported exactly that. After I made the fixture stop rewriting an existing plan, all 24 passed.

- **Behavior change.** An `in_progress` task approved before this change is blocked at the gate until a new review round runs. `done` tasks are still read by verdict only, as before.
- **Limit.** In a writable workspace a consistent manifest, hashes included, can be forged. It is consistency evidence, not proof. The Shadow v2 close gate does not check the new hashes.

Raw logs: [new tests run against the old verifier](./evidence/02-hash-binding/new-tests-against-old-verifier.tap) · [integration 27/27](./evidence/02-hash-binding/integration-contract-27-of-27.tap) · [first run (fixture defect, 9 failures)](./evidence/02-hash-binding/first-run-fixture-defect-9-failures.tap) · [after the fixture fix](./evidence/02-hash-binding/genuine-evidence-gate-tests-after-fixture-fix.tap) · [wrapper-driven suites 233/233](./evidence/02-hash-binding/wrapper-driven-suites-233-of-233.tap) · [full suite on the merged main](./evidence/02-hash-binding/on-merged-main-full-suite/)

## 5. New model registrations and the default reviewer

| Vendor | Routes added | Basis for the model ID |
|---|---|---|
| agy | Gemini 3.8 Flash high, medium, low (3) | IDs the agy CLI recorded in its own logs |
| claude | Opus 5.5, Sonnet 5.5 (+xhigh), Haiku 5.5, Fable 5.1 (5) | Model IDs the session reports (`claude-opus-5-5` and so on); both dotted and dashed aliases registered |
| codex | GPT-6.1 Sol and GPT-6 Astra (each default, medium, high, xhigh), GPT-6 Luna (9) | Slugs in the local codex model catalog (refreshed 2026-10-22) |

- **Checked without running a real CLI.** I only read the catalog cache and logs and did not run `agy`, `claude` or `codex`. This is a deliberate choice so that no ID is guessed.
- **Default OpenAI reviewer.** `codex-gpt-6.1-sol-medium` (the user's decision). The catalog reports low as the default effort for 6.1 Sol and Astra, so the unsuffixed aliases are pinned to medium. The catalog's own description presents 6.1 Sol as near-Astra performance at lower cost, so I did not declare Astra the successor of the previous default, Terra.
- **Seven version-less aliases** (`claude-sonnet-latest` and so on) now point to the new generation. The versioned aliases and existing routes are unchanged. The existing Sonnet 5 / Fable 5 adversarial review pair is also unchanged, and Sonnet 5.5 / Fable 5.1 is a new pair.
- **One test the default change broke.** The adversarial-evaluator test that named Terra explicitly. The evaluator must be in the default reviewer set, so it errored, and I updated it to the new default's name. The assertions are unchanged.
- **Not registered.** Gemini 4 Argon, because there is no local evidence for its model ID. I also did not touch the role-routing docs or the agent presets (the Terra and Astra naming question).

Raw logs: [new tests run against the old registry](./evidence/03-model-registry/new-tests-against-old-registry.tap) · [new registry tests](./evidence/03-model-registry/new-registry-tests.tap) · [right after the default change (1 failure)](./evidence/03-model-registry/first-run-after-default-change-232-of-233.tap) · [22 default-dependent tests](./evidence/03-model-registry/default-reviewer-dependent-tests-22-of-22.tap)

## 6. Verification results

All runs used frozen copies, with a `PATH` that cannot reach the real CLIs. The method is in [evidence/README.md](./evidence/README.md).

| Scope | Result | Notes |
|---|---|---|
| Full suite on the SIGPIPE-fix branch (859 tests) | 857 ok | 1 of them an intended skip. The 2 failures are baseline failures that predate the fix and fail identically on both parents. This fix did not repair them, so SIGPIPE is not their cause. I did not investigate the cause. |
| Hash-binding branch: integration suite | 27 / 27 | GUARD 2, TC-01 to TC-21, PARITY-01, KL-3 to KL-5 |
| Hash-binding branch: wrapper-driven suites (233 tests) | 233 / 233 | external_review, run_codeguide, doc_garden, integration, shadow_v2 |
| Registry branch: wrapper-driven suites + gate | 264 / 265 | The 1 failure is the Terra-explicit test from section 5; after the fix the 22 default-dependent tests all pass |
| Merged main (registry + SIGPIPE): external_review + pipe_safety | 84 / 84 ok | 1 of them an intended skip |
| Merged main (registry + SIGPIPE): gate and evidence tests | 31 / 31 | |
| Merged main (registry + SIGPIPE): the rest (190 tests) | 190 / 190 | 0 failures |
| Main with hash binding merged: full suite | 863 ok of 865 | 1 of them an intended skip. The 2 failures are the same baseline failures |
| After all merges: packaging, integration, front_cli and others | 130 / 130 | |

## 7. What remains, and limits

- The 2 baseline failures (a done task's evaluator report for an earlier plan version, and JSON issue ids) were not investigated.
- The Shadow v2 close gate does not check the new hashes, and the evidence remains forgeable consistency evidence.
- Work that bypasses the harness, the review-requirement field the agent writes, and the approval history of completed tasks remain outside the gate, as before (KL-3 to KL-5).
- The random SIGPIPE race itself was not reproduced (section 2).
- Gemini 4 Argon, the role-routing docs and the agent presets need a user decision.

## 8. Reports from the earlier stages

These are HTML files, so GitHub shows their source. Download one and open it in a browser to see it rendered. Both are in Korean.

- [External review approval gate fix report](./external-review-gate-hardening.html): a record of reproducing the five defects raised in an audit with mock tests and fixing only the ones that were confirmed
- [Integration contract verification report](./adversarial-gate-integration.html): a record of finding and fixing one verifier that disagreed with the contract when the adversarial review rule and the approval gate were combined
