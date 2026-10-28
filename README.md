# codeguide

**한국어** | [English](./README.en.md)

`codeguide`는 아키텍처 거버넌스, 의사결정 추적성, 문서 라이프사이클 자동화를 위해 만든 결과 중심(outcome-first) LLM 협업 스킬입니다.

부트캠프 파이널 프로젝트에서 마크다운 문서를 수동으로 관리하던 방식에서 출발해, 프로젝트 맥락과 결정 사항, 계획, 검증 규칙을 반복 가능하게 동기화하는 셸 기반 워크플로로 발전했습니다.

## 검증된 결과

> 측정일: 2026-10-29 (KST). 아래 결과는 전체 867개 Bats 테스트가 아니라 50개 fast quality gate와 선별된 보안·대규모 입력 실험 기준입니다.

- **반복 안정성:** 50개 fast gate를 5회 실행해 250/250 통과, 관측된 flake 0건. 중앙값 79초, 최대 80초였습니다.
- **승인 gate 방어:** 증거 변조 20종과 잘못된 waiver 8종, 총 28/28을 차단했습니다.
- **대규모 입력:** 8,000개 ID, 1,500개 추적 파일, 1,500개 변경 경로 시나리오를 5회 실행해 20/20 통과했습니다. 각 실행은 13초였습니다.

이 결과는 해당 범위의 재현 가능한 기술 검증이며, 전체 suite의 무결함이나 실제 팀 생산성 향상을 증명하지는 않습니다. [한국어 상세 보고서](./case-studies/portfolio-metrics-2026-10-29.html) · [English report](./case-studies/portfolio-metrics-2026-10-29.md) · [원시 증거](./case-studies/evidence/08-portfolio-metrics-20261029/)

## 문제의식

LLM을 활용한 개발은 보통 다음 지점에서 쉽게 흔들립니다.

- 세션이 바뀌면 맥락이 사라집니다.
- 아키텍처 결정을 내렸지만 기록이 남지 않습니다.
- 구현이 합의된 계획에서 점점 벗어납니다.
- 관련 없는 파일이 현재 작업 맥락을 오염시킵니다.
- 문서 품질이 개인 습관에 의존합니다.

`codeguide`는 문서를 시스템의 기준 기록으로 삼는 방식(docs-as-system-of-record)과 가벼운 자동화 스크립트로 이런 문제를 줄입니다. 실행 환경에 실제로 필요한 만큼만 문서화하고 검증하는 데 초점을 둡니다.

## 핵심 구조

- `docs/task`, `docs/shadow`, `docs/decisions`는 진행 중인 작업, 현재 시스템 상태, 아키텍처 결정을 분리합니다.
- 중요한 변경, 설계 결정, 인수인계 작업은 `Why`, `What`, `How`, `Where`, `Verify`의 다섯 축으로 기록합니다.
- Plan Ping-Pong Loop는 필요할 때만 외부 평가를 실행하고 계획을 점진적으로 수렴시킵니다.
- Change Scope Policy는 `docs-only` 작업과 `code-or-runtime` 작업을 구분합니다.
- 실제로 위임이 일어나면 오케스트레이션 문서에 감독 agent, 위임받은 sub-agent, 담당 범위를 기록합니다.
- 프로젝트 문서는 선택한 프로젝트 루트의 `docs/`에 두고 backend/frontend/app 같은 하위 단위와 함께 추적합니다.
- 여러 CLI가 symlink로 공유하는 재사용 스킬 프로젝트는 예외적으로 스킬 패키지 루트와 프로젝트 수준 `docs/` 루트를 분리할 수 있습니다.

## 이 스킬이 하는 일

`codeguide`의 핵심은 셸 스크립트 모음이 아니라, agent가 설계·리팩터링·리뷰·디버깅 작업에서 따라야 할 운영 규칙과 문서 워크플로입니다.

주요 원칙은 다음과 같습니다.

- 한국어 대화에서는 정확성과 필요한 기술 깊이를 유지하면서도 쉬운 단어와 익숙한 예를 사용하는 ELI5 설명 방식을 적용합니다. 이 지침은 upstream [ELI5 skill](https://github.com/anthropics/claude-plugins-community/blob/main/eli5/skills/eli5/SKILL.md)을 참고했습니다.
- 중요한 구현 전에 작업 목적, 제약, 위험을 문서화합니다.
- 중요한 선택은 `Why/What/How/Where/Verify` 다섯 축으로 설명한 `decision-*` 기록으로 남깁니다.
- 계획이 필요한 작업은 `PLAN-*`과 리뷰 문서를 통해 검토 가능하게 만듭니다.
- 진행 중인 작업, 현재 시스템 상태, 아키텍처 결정을 서로 다른 문서로 분리합니다.
- 인수인계 전에 문서 검증과 런타임 검증을 함께 실행합니다.

즉, 이 저장소의 주인공은 `sh` 파일이 아니라 LLM이 일관되게 행동하도록 만드는 협업 계약입니다.

## 스킬로 사용하는 방법

셸 명령을 직접 외우기보다 agent에게 `codeguide` 기준으로 작업하라고 요청할 때 이 스킬의 가치가 가장 큽니다.

요청 예시:

- `codeguide 기준으로 이 변경 설계 리뷰해줘`
- `codeguide로 리팩터링 계획부터 세우고 Why/What/How/Where/Verify로 정리해줘`
- `codeguide로 이 버그를 repro -> hypothesis -> fix -> verification 흐름으로 잡아줘`
- `high risk로 보고 plan review 한 번 더 돌려줘`
- `docs도 같이 동기화하면서 진행해줘`

일반적인 흐름은 다음과 같습니다.

1. Agent가 현재 작업을 `design`, `refactor`, `review`, `debug` 중 어떤 흐름으로 처리할지 판단합니다.
2. 작업 크기와 위험에 따라 프로젝트 루트의 `docs/`에 task, decision, plan, orchestration 문서가 필요한지 결정합니다.
3. 위험도가 높으면 계획 리뷰 루프를 실행하며, high risk에는 adversarial review가 필요합니다.
4. 구현 후 shadow와 문서 상태를 동기화하고 필요한 lint/test/e2e를 실행합니다.
5. 마지막으로 근거와 검증이 충분한지 확인하고, 반복해도 결론이 실질적으로 달라지지 않으면 멈춥니다.

사용자가 스크립트를 직접 조작하게 하는 것이 목적이 아니라, agent가 이 스킬의 정책을 따르게 하는 것이 목적입니다.

## Sub-Agent 오케스트레이션

이 스킬은 solo 작업만 가정하지 않습니다. 기본 모델은 감독 lead architect가 방향을 정하고, 사용자가 명시적으로 요청했으며 작업이 충분히 크고 분리 가능할 때 역할별 sub-agent가 나누어 맡는 방식입니다.

- planner: 계획 작성
- reviewer: 계획이나 변경 제안의 누락·모순·규칙 위반을 비판적으로 검토
- implementation agent: 실제 코드 변경
- validation agent: 테스트·검증·인수인계 준비 상태 확인
- evaluator: 보고서에 `accept | revise | blocked` 판정을 기록하며, reviewer와 마찬가지로 승인보다 결함 탐색을 우선

실제로 위임이 일어나면 이 역할 분리를 `docs/orchestration/<task-id>/ORCH.md`에 기록합니다. `execution_mode`, `supervisor_agent`, `planner_agents`, `reviewer_agents`, `implementation_agents`, `validation_agents`, `owned_scopes`, `risk_preflight_status`, `approval_ref` 같은 필드로 추적합니다.

Sub-agent나 외부 evaluator를 시작하기 전에 main supervising lead architect가 risk preflight를 먼저 실행해야 합니다. 안전, 개인정보, 권한, 파괴적 작업, 외부 부작용, 민감정보, 범위, 사용자 결정 gate가 적용되면 위임이나 외부 리뷰를 시작하지 않습니다. Ping-pong은 사용자가 정확한 다음 단계를 승인한 뒤에만 시작합니다.

특히 `/codeguide`로 코드 작성이나 구현을 요청하면서 `서브에이전트` 계열 표현을 명시하면, 별도 사유가 없는 한 planner/reviewer/evaluator/implementation/validation 역할을 sub-agent에게 나누고 main agent는 대부분의 코드를 직접 작성하기보다 tech lead architect이자 supervisor로 행동합니다.

위임이나 외부 리뷰가 실제로 있었다면 `docs-only` 작업에도 오케스트레이션 규칙을 적용합니다. 코드를 실행하지 않는 계획·리뷰 단계라도 주 작성자와 리뷰 방식을 문서에 기록합니다.

## 내부 자동화

README의 중심은 아니지만, 다음 스크립트가 운영 규칙을 자동화합니다.

- [`scripts/codeguide`](./scripts/codeguide): 아래 스크립트를 subcommand 하나로 묶은 단일 진입점([단일 진입점](#단일-진입점-scriptscodeguide) 참고)
- [`scripts/run_codeguide.sh`](./scripts/run_codeguide.sh): 문서 라이프사이클 시작·동기화와 런타임 검증 흐름의 진입점
- [`scripts/run_external_plan_reviews.sh`](./scripts/run_external_plan_reviews.sh): 주 작성 도구를 제외한 두 evaluator에게 `PLAN-*` 리뷰를 요청하고 보고서를 만든 뒤 멈추는 반자동 ping-pong 리뷰 명령
- [`scripts/doc_garden.sh`](./scripts/doc_garden.sh): task, decision, orchestration, shadow 문서 갱신
- [`scripts/init_docs_scaffold.sh`](./scripts/init_docs_scaffold.sh): 프로젝트 루트의 기본 `docs/` 구조와 템플릿 생성
- [`scripts/validate_docs.sh`](./scripts/validate_docs.sh): 문서 일관성·최신성·리뷰/오케스트레이션 규칙·secret scan 검증
- [`scripts/check_english_docs.sh`](./scripts/check_english_docs.sh): 선별된 운영 문서의 영어 정책 검증
- [`scripts/shadow_policy_loader.py`](./scripts/shadow_policy_loader.py): shadow 정책 Markdown에서 fenced `yaml` registry block만 선언으로 읽고 probe adapter 구현과의 일치 여부 확인
- [`scripts/shadow_evidence_probe.py`](./scripts/shadow_evidence_probe.py): static `AdapterRegistry`에 등록된 validator만 실행해 shadow effect candidate를 결정론적 probe 결과로 변환
- [`scripts/shadow_review_queue.py`](./scripts/shadow_review_queue.py): 근거가 부족한 effect candidate를 제한된 human review queue로 변환
- [`scripts/shadow_llm_candidate_wrapper.py`](./scripts/shadow_llm_candidate_wrapper.py): LLM 초안을 승격 불가능한 candidate artifact로 감쌈
- [`scripts/shadow_user_decision_wrapper.py`](./scripts/shadow_user_decision_wrapper.py): final apply 승인과 human fact-evidence 결정을 위한 보호된 user_decision artifact 생성
- [`scripts/shadow_apply_gate.py`](./scripts/shadow_apply_gate.py): 감독된 dry-run 모드에서 최종 shadow apply 승인 조건 확인
- [`scripts/shadow_effect_writer.py`](./scripts/shadow_effect_writer.py): gate를 통과한 `confirmed/unknown/blocked/stale` 구조화 effect record를 shadow effect_map에 기록하고, blocked 결과에는 가능한 다음 probe/decision 명령을 `next_actions`로 제안
- [`tests/`](./tests/): 자동화 기능별로 나눈 Bats 회귀 테스트 모음

스크립트는 스킬의 본체라기보다 운영 원칙을 반복 가능하게 만드는 구현 계층입니다.

High-risk 작업에서는 `run_external_plan_reviews.sh`가 task 또는 연결된 decision의 `risk_level`을 읽습니다. 사용자가 adversarial evaluator를 지정하지 않아도 주 작성자가 아닌 reviewer 한 명을 adversarial pass로 자동 승격합니다.

## 런타임 환경 계약

지원 도구: bash >= 3.2, python3 >= 3.9, bats-core >= 1.5, git. Python 개발 의존성은 `requirements-dev.txt`의 pytest뿐이며, 런타임 스크립트는 표준 라이브러리만 사용합니다.

```bash
scripts/check_env.sh                                 # 도구 환경 진단과 원인별 해결 안내; scripts/codeguide doctor와 동일
python3 -m pip install -r requirements-dev.txt      # 개발 의존성 설치
scripts/check_all.sh                                 # 환경 + Bats + pytest + strict docs + 영어 정책 통합 gate; scripts/codeguide check와 동일
```

깨끗한 checkout에서는 `check_all.sh` 하나로 전체 품질 gate를 재현할 수 있습니다. 테스트는 호출한 셸의 환경변수에 의존하지 않습니다. `tests/codeguide_helper.bash`의 `setup()`이 `CODEX_SANDBOX*`, `CODEGUIDE_SOURCE_ROOT`, `CODEGUIDE_*_BIN`을 초기화하고, sandbox 동작 테스트가 필요한 변수를 테스트별로 주입합니다.

`validate_docs.sh --gate external-review [--task-id <id>]`는 advisory/strict 문서 검사의 fail-closed 버전입니다. 구현 시작 전 external review await gate만 평가하여 필요 없거나 충족되면 0, 필요하지만 충족되지 않으면 1을 반환합니다. `run_codeguide.sh`는 task를 `in_progress`나 `done`으로 옮기기 전에 이를 실행합니다. `validate_docs.sh --format json`은 stdout에 JSON 객체 하나만 출력하고(`{mode, project_root, format_version, issues[{tier,id,caller,message}], counts, result}`), 진단은 stderr로 보냅니다. 종료 코드는 text mode와 같습니다. 각 issue의 `id`는 문제를 보고한 check 함수 이름이고 `caller`는 이를 호출한 상위 함수입니다. 최상위 흐름은 둘 다 `main`을 사용합니다. 따라서 소비자는 `(id, caller, message prefix)`로 규칙을 구분할 수 있으며, check 함수 이름을 바꾸면 id도 바뀌므로 commit에 명시해야 합니다. 기본 `--format text` 출력은 byte 단위로 고정됩니다.

`scripts/check_all.sh --metrics-out <file>`은 실행할 때마다 단계별 결과와 소요 초를 JSONL 한 줄로 추가해 runtime/flake 추세 수집의 기반을 만듭니다. 이 기능은 관찰 전용이며 옵션이 없을 때 동작과 출력은 바뀌지 않습니다. `scripts/packaging_smoke.py`는 전체 스킬 트리를 SHIP/DEV-ARTIFACT/UNKNOWN으로 분류하고 배포 manifest에 허용되지 않은 항목이나 UNKNOWN이 있으면 read-only hygiene 검사를 실패시킵니다.

## 검증과 신뢰성

자동화가 스스로 무엇을 검증하며 어디까지 보장하는지 설명합니다. 근거 보고서는 [`case-studies/`](./case-studies/)에 있습니다.

- **Fail-closed 승인 gate.** `validate_docs.sh --gate external-review`는 `run_codeguide.sh`가 task를 `in_progress`나 `done`으로 옮기기 전에 실행합니다. 필요한 모든 external review가 완전한 근거 세트를 남겼을 때만 구현을 시작할 수 있습니다. 요청, 정제된 응답, provenance manifest의 task·plan version·round·route가 일치해야 하며 응답·요청·plan 파일은 리뷰 시 기록된 SHA-256과 각각 일치해야 합니다. `verdict: accept` 파일만 있는 경우, 수정된 응답, 리뷰 후 변경된 plan이나 요청, hash 도입 전에 만든 manifest, 누락된 manifest, 기록된 사용자 결정이 없는 waiver는 통과하지 못합니다.
- **Adversarial review 단일 계약.** Wrapper parser(`run_external_plan_reviews.sh`), evidence verifier(`validate_docs_review_evidence.py`), Shadow v2 close gate는 같은 필드 규칙을 적용합니다. 네 debate key가 모두 존재하고 `residual_risk`는 비어 있지 않아야 하며, 나머지 세 필드는 `accept`일 때만 비울 수 있습니다. `tests/review_contract_integration.bats`는 wrapper와 verifier가 응답 하나라도 다르게 판단하면 실패합니다. Mock runner 앞의 `PATH` tripwire는 실제 `agy`, `claude`, `codex` 호출을 거부하고 기록합니다.
- **실패 가능성이 검증된 테스트.** 계약 테스트는 이전 코드에서 실제로 실패하는지 확인했고, 기억한 개수가 아니라 수정하지 않은 baseline과 suite를 비교했습니다. 기본 테스트는 실제 `agy`를 실행하지 않습니다. Live model catalog 비교는 `CODEGUIDE_LIVE_AGY_CATALOG=1`일 때만 실행됩니다. `tests/pipe_safety.bats`는 `grep -q`, `head`처럼 consumer가 일찍 종료하는 pipeline을 `scripts/`에서 막습니다. `set -o pipefail` 환경에서는 이런 pipeline이 올바른 결과도 실패로 바꿀 수 있기 때문입니다.
- **알려진 한계.** 현재 동작으로 테스트에 고정된 `KL-*` 또는 후속 작업으로 추적되는 항목이며, 해결됐다고 주장하지 않습니다. Shadow v2 close gate는 plan과 request hash를 검사하지 않습니다. Harness를 건너뛴 작업은 gate 대상이 아닙니다. 리뷰 요구 여부는 agent가 작성하는 필드입니다. 완료된 task의 승인 기록은 다시 검사하지 않습니다. 근거는 일관성 증명이지 attestation이 아니므로 쓰기 가능한 workspace에서는 일치하는 manifest를 위조할 수 있습니다.

Case study는 작업 당시 상태를 담은 시점별 보고서입니다. HTML 보고서는 한국어이고 Markdown 보고서는 영어입니다.

- [포트폴리오 검증 지표](./case-studies/portfolio-metrics-2026-10-29.html) — 한국어 HTML. fast gate 반복 안정성, 승인 gate 공격 변형, 대규모 입력을 2026-10-29에 재측정했습니다: [`evidence/08-portfolio-metrics-20261029/`](./case-studies/evidence/08-portfolio-metrics-20261029/)
- [External review 승인 gate 강화](./case-studies/external-review-gate-hardening.html) — 한국어 HTML. 핵심 테스트는 이전 commit에서 다시 실행했습니다: [`evidence/05-gate-hardening-regenerated/`](./case-studies/evidence/05-gate-hardening-regenerated/)
- [Adversarial 규칙과 승인 gate 통합](./case-studies/adversarial-gate-integration.html) — 한국어 HTML. 핵심 테스트는 이전 commit에서 다시 실행했습니다: [`evidence/06-adversarial-integration-regenerated/`](./case-studies/evidence/06-adversarial-integration-regenerated/)
- [테스트 신뢰성 강화](./case-studies/test-reliability-hardening.md) — 영어 문서이며 [한국어 HTML 버전](./case-studies/test-reliability-hardening.html)도 있습니다. `pipefail` 환경의 early-exit pipeline(14곳, 3곳 재현), 기본 실행의 실제 `agy` 호출 제거, 승인된 리뷰의 plan/request hash binding, model registry 갱신을 다룹니다. 인용한 raw test log는 [`case-studies/evidence/`](./case-studies/evidence/)에 있습니다.

## 단일 진입점: `scripts/codeguide`

개별 스크립트 경로를 외우는 대신 `scripts/codeguide`가 모든 자동화 진입점을 subcommand 하나로 제공합니다. 각 subcommand는 나머지 인자를 quoting을 유지한 채 대상 도구에 `exec`로 전달하므로 `scripts/codeguide <subcommand> --help`를 실행하면 대상 도구의 사용법이 표시됩니다.

```bash
scripts/codeguide                       # subcommand 목록과 한 줄 설명; 인자 없음/-h/--help/help 모두 동일
scripts/codeguide <subcommand> --help   # 대상 도구의 사용법으로 전달
```

| Subcommand | 대상 스크립트 | 목적 |
| --- | --- | --- |
| `doctor` | `check_env.sh` | 도구 환경 진단 |
| `check` | `check_all.sh` | 통합 품질 gate |
| `validate` | `validate_docs.sh` | 문서 일관성·최신성·secret scan 검증 |
| `docs-sync` | `doc_garden.sh` | task/decision/orchestration/shadow 문서 갱신 |
| `scaffold` | `init_docs_scaffold.sh` | 프로젝트 `docs/` 기본 구조 생성 |
| `review` | `run_external_plan_reviews.sh` | Ping-pong external plan review round 실행 |
| `shadow-impact` | `shadow_impact_report.py` | shadow 문서를 갱신하지 않고 변경된 source 보고 |
| `shadow-coverage` | `shadow_coverage_report.py` | 어떤 shadow 문서에도 포함되지 않은 변경 source 보고 |
| `shadow-metrics` | `shadow_metrics_report.py` | shadow 문서의 token 비용과 크기를 제한값과 비교 |
| `shadow-digest` | `shadow_source_digest.py` | source-of-truth content digest 계산·검증 |

`check_all.sh`(`scripts/codeguide check`)는 재현 가능한 부분 실행과 실패 진단 artifact 보존을 위해 다음 두 옵션을 추가로 지원합니다.

- `--suite <fast|contract|external|shadow|full>`: Bats 단계를 지정한 파일 부분집합으로 제한합니다. 기본값 `full`은 옵션 없는 실행과 똑같이 전체 `tests/` 트리를 실행합니다. Suite 구성 파일이 하나라도 없으면 어떤 단계도 시작하기 전에 명확하게 실패합니다. Pytest 단계는 `full`에서만 실행하며 나머지에서는 skip으로 보고합니다.

  ```bash
  scripts/codeguide check --suite fast --skip-pytest   # 빠른 부분집합만 재현
  ```

- `--artifacts <dir>`: 각 단계의 stdout과 stderr를 `<dir>/<NN>-<stage>.log`에 tee하고, Bats 단계의 JUnit 보고서도 `<dir>`에 남깁니다(`--report-formatter junit --output <dir>`). 종료 코드 의미는 바뀌지 않으며 summary에 artifact 디렉터리가 표시됩니다.

  ```bash
  scripts/codeguide check --artifacts .artifacts/check-all   # 로그와 JUnit 보존
  ```

## 스크립트를 직접 호출할 때

`scripts/codeguide`에 포함되지 않은 저수준 도구가 필요하면 `scripts/` 아래 명령을 직접 호출할 수 있습니다. 예를 들어 shadow effect pipeline의 review queue/decision/apply-gate 단계나 `run_codeguide.sh` 통합 모드가 해당합니다.

```bash
cd <skill-dir>
scripts/run_codeguide.sh /path/to/project --mode auto
python3 scripts/shadow_policy_loader.py --project-root /path/to/project --adapter-module scripts/shadow_evidence_probe.py --check-parity
python3 scripts/shadow_evidence_probe.py --project-root /path/to/project --validator-id py.ast.call_match@v1 --source-file src/app.py --callee save
python3 scripts/shadow_review_queue.py --input probe.jsonl --task-id shadow-effect-map-01
python3 scripts/shadow_user_decision_wrapper.py --project-root /path/to/project --output decision.json --decision-id UD-001 --decision-type final_shadow_apply --answer yes --decided-by gm --decided-at 2026-05-03 --expires-at 2026-05-10 --candidate-id LC-... --record record.json --target-shadow-file packages/app/effects.md --rationale "Approve exact record" --source-ref TASK-shadow-effect-map-01
bats tests/
```

`run_external_plan_reviews.sh`(`scripts/codeguide review`)는 기본적으로 CLI의 기본 model을 사용하며 사용자가 override를 지정하지 않으면 특정 version 이름을 hardcode하지 않습니다. 긴 prompt는 셸 인자로 전달하지 않고 `docs/orchestration/<task-id>/external-cli/<plan-version>/<round>/` 아래의 Markdown 요청/응답 파일로 왕복합니다. 외부 CLI에 보내는 짧은 bash 명령은 stdout redirection, `tee`, `--output-last-message` 같은 도구별 옵션으로 절대 command-output 경로를 지정해야 합니다. Prompt 안에서 경로만 언급하는 것은 충분하지 않습니다. Wrapper는 raw command output을 저장하기 전에 민감한 값을 가리고 raw capture를 삭제합니다. 요청에는 `Why/What/How/Where/Verify` 축이 포함되고, 유효한 응답은 parser가 읽을 수 있는 bullet field 형식을 따르며, 보존 파일은 저장 전에 민감정보를 가립니다. 이 명령은 리뷰 보고서를 만든 뒤 멈추며 다음 `PLAN-v1.1`을 자동 생성하지 않습니다.

이 명령들은 스킬 사용의 본질이라기보다 스킬의 운영 상태를 재현하고 검증하기 위한 보조 인터페이스입니다.

## 프로젝트 구조

```text
codeguide/
├── README.md
├── README.en.md
├── SKILL.md
├── agents/
├── case-studies/
├── references/
├── scripts/
└── tests/
```

- `README.md`: 기본 한국어 안내서
- `README.en.md`: 영어 안내서
- `SKILL.md`: 운영 계약과 워크플로 정책
- `agents/`: 스킬용 agent 설정
- `case-studies/`: 시점별 검증·신뢰성 작업 보고서. 한국어 HTML, 최신 보고서의 영어 Markdown, 인용한 raw test log가 있는 `evidence/`를 포함하며 프로젝트 수준 `docs/` 루트와 의도적으로 분리합니다.
- `references/`: 거버넌스, 아키텍처, 리뷰 기준 문서
- `scripts/`: 실행 가능한 자동화 계층
- `tests/`: 셸 도구 회귀 테스트

## 발전 과정

- 다른 스킬 기술에서 영감을 얻음
- 부트캠프 파이널 프로젝트에서 마크다운을 수동 운영
- 컨텍스트 손실과 결정 drift를 반복해서 경험
- 반복 가능한 문서 라이프사이클을 위해 셸 스크립트로 통합
- Supervising architect 모델을 기반으로 multi-agent 오케스트레이션 규칙 추가
- 일관성·최신성·secret hygiene 검증 gate 추가
