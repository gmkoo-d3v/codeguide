# codeguide

`codeguide`는 아키텍처 거버넌스, 의사결정 추적성, 문서 라이프사이클 자동화를 위해 만든 문서 중심 LLM 협업 스킬입니다.

부트캠프 파이널 프로젝트에서 수동으로 마크다운 문서를 관리하던 방식에서 출발해, 프로젝트 맥락과 결정 사항, 계획, 검증 규칙을 반복 가능하게 동기화하는 쉘 기반 워크플로우로 발전시켰습니다.

## 문제의식

LLM을 활용한 개발은 보통 다음 지점에서 쉽게 흔들립니다.

- 세션이 바뀌면 컨텍스트가 사라진다
- 아키텍처 결정은 했지만 기록이 남지 않는다
- 구현이 합의된 계획에서 점점 이탈한다
- 관련 없는 파일이 현재 작업 맥락을 오염시킨다
- 문서 품질이 개인 습관에 의존한다

`codeguide`는 이런 문제를 docs-as-system-of-record 방식과 가벼운 자동화 스크립트로 줄이는 데 초점을 둡니다.

## 핵심 구조

- `docs/task`, `docs/shadow`, `docs/decisions`로 활성 작업, 현재 시스템 상태, 아키텍처 결정을 분리합니다
- 모든 주요 변경을 `Why`, `What`, `How`, `Where`, `Verify` 5축으로 기록합니다
- Plan Ping-Pong Loop로 외부 평가를 거치며 계획을 점진적으로 수렴시킵니다
- Change Scope Policy로 `docs-only`와 `code-or-runtime` 작업을 구분합니다
- 오케스트레이션 문서로 supervising agent, delegated sub-agents, owned scopes를 기록합니다
- 워크스페이스 문서는 repo 안이 아니라 `../docs`에 두어 저장소 잡음을 줄이고 공용 소스 오브 트루스를 유지합니다

## 이 스킬이 하는 일

`codeguide`는 쉘 스크립트 모음이라기보다, Codex가 설계·리팩터링·리뷰·디버그 작업을 수행할 때 따를 운영 규칙과 문서 워크플로우를 제공하는 스킬입니다.

사용자가 기대해야 하는 핵심은 다음과 같습니다.

- 구현 전에 작업 목적, 제약, 리스크를 문서화합니다
- 중요한 선택은 `decision-*`로 남기고 5축 `Why/What/How/Where/Verify`로 설명합니다
- 계획이 필요한 작업은 `PLAN-*`과 review 문서로 검토 가능한 상태를 만듭니다
- 활성 작업, 현재 시스템 상태, 아키텍처 결정을 서로 다른 문서로 분리합니다
- handoff 전에는 문서와 실행 검증을 함께 거치게 합니다

즉 이 저장소의 주인공은 `sh` 파일이 아니라, LLM이 일관된 방식으로 일하게 만드는 협업 규약입니다.

## 스킬로서의 사용법

이 스킬은 보통 사용자가 직접 쉘 명령을 외우는 방식보다, Codex에게 `codeguide` 기준으로 일해달라고 요청할 때 의미가 있습니다.

예를 들면 이런 요청에 맞습니다.

- `codeguide 기준으로 이 변경 설계 리뷰해줘`
- `codeguide로 리팩터링 계획부터 세우고 Why/What/How/Where/Verify로 정리해줘`
- `codeguide로 이 버그를 repro -> hypothesis -> fix -> verification 흐름으로 잡아줘`
- `high risk로 보고 plan review 한 번 더 돌려줘`
- `docs도 같이 동기화하면서 진행해줘`

사용 흐름은 대체로 이렇습니다.

1. Codex가 현재 작업을 `design`, `refactor`, `review`, `debug` 중 어떤 흐름으로 다룰지 정합니다.
2. 필요하면 workspace `../docs` 아래에 task, decision, plan, orchestration 문서를 만들거나 갱신합니다.
3. 변경 위험이 크면 plan review loop를 돌리고, high risk면 adversarial review를 요구합니다.
4. 구현 후에는 shadow와 문서 상태를 다시 맞추고, 필요 시 lint/test/e2e를 실행합니다.
5. 마지막에 문서 검증과 handoff 가능한 상태인지 확인합니다.

핵심은 사용자가 스크립트를 조작하는 것이 아니라, 에이전트가 이 스킬의 정책을 따라 행동하게 만드는 데 있습니다.

## 서브에이전트 오케스트레이션

이 스킬은 solo 작업만 상정하지 않습니다. 기본 모델은 supervising lead architect가 방향을 잡고, 필요하면 역할별 서브에이전트가 분리된 책임을 맡는 방식입니다.

- planner: 계획 초안 작성
- reviewer: 계획 또는 변경안의 허점, 모순, 누락, 규칙 위반을 비판적으로 검토
- implementation agent: 실제 코드 수정
- validation agent: 테스트, 검증, handoff 확인
- evaluator는 report 문서에서 `accept | revise | blocked` 판단을 남기는 평가 주체이지만, reviewer와 마찬가지로 승인형보다 결함 탐지형 태도를 기본으로 둡니다

이 역할 분리는 `docs/orchestration/ORCH-<task-id>.md`에 기록되며, `execution_mode`, `supervisor_agent`, `planner_agents`, `reviewer_agents`, `implementation_agents`, `validation_agents`, `owned_scopes` 같은 필드를 통해 추적됩니다.

특히 `/codeguide`로 코드 작성이나 구현을 요청하면서 `서브에이전트` 계열 표현을 명시한 경우에는, 특별한 이유가 없으면 메인 에이전트가 직접 코드를 주로 쓰기보다 planner/reviewer/evaluator/implementation/validation 역할을 서브에이전트에 배분하고 메인 에이전트는 tech lead architect 겸 감독 역할을 수행하는 것이 기본값입니다.

오케스트레이션 규칙은 `docs-only` 작업에서도 유지됩니다. 즉 코드를 실행하지 않는 계획/리뷰 단계라도, 누가 primary 작성자였고 어떤 review mode를 썼는지는 오케스트레이션 문서에 남겨야 합니다.

## 내부 자동화 구성

README의 중심은 아니지만, 이 스킬은 몇 개의 쉘 스크립트로 운영 규칙을 자동화합니다.

- [`scripts/run_codeguide.sh`](./scripts/run_codeguide.sh): docs lifecycle 시작, 동기화, 검증, runtime validation 진입점
- [`scripts/run_external_plan_reviews.sh`](./scripts/run_external_plan_reviews.sh): primary 작성 도구를 제외한 다른 evaluator 둘에게 `PLAN-*` 리뷰를 요청하고, report 문서를 생성한 뒤 멈추는 반자동 ping-pong 리뷰 명령
- [`scripts/doc_garden.sh`](./scripts/doc_garden.sh): task, decision, orchestration, shadow 문서 갱신
- [`scripts/init_docs_scaffold.sh`](./scripts/init_docs_scaffold.sh): workspace `../docs` 기본 구조와 템플릿 생성
- [`scripts/validate_docs.sh`](./scripts/validate_docs.sh): 문서 정합성, 최신성, review/orchestration 규칙, secret scan 검증
- [`scripts/check_english_docs.sh`](./scripts/check_english_docs.sh): 내부 운영 문서의 영어 정책 점검
- [`tests/codeguide.bats`](./tests/codeguide.bats): 위 자동화의 회귀 테스트

즉 스크립트는 스킬의 본체라기보다, 스킬 운영 원칙을 반복 가능하게 만드는 구현 레이어입니다.

고위험 작업에서는 `run_external_plan_reviews.sh`가 task나 linked decision의 `risk_level`을 읽어, 사용자가 adversarial evaluator를 명시하지 않아도 non-primary reviewer 중 하나를 자동으로 adversarial pass로 승격시킵니다.

## 수동 실행이 필요할 때

자동화나 테스트 관점에서 직접 실행할 수도 있습니다.

```bash
export CODEGUIDE_ROOT="$HOME/.codex/skills/codeguide"
"$CODEGUIDE_ROOT/scripts/init_docs_scaffold.sh" /path/to/project
"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" /path/to/project --mode auto
"$CODEGUIDE_ROOT/scripts/run_external_plan_reviews.sh" /path/to/project \
  --task-id search-nav-01 \
  --plan-version v1.0 \
  --primary-tool codex \
  --review-round r01
"$CODEGUIDE_ROOT/scripts/validate_docs.sh" /path/to/project --mode strict
bats "$CODEGUIDE_ROOT/tests/codeguide.bats"
```

`run_external_plan_reviews.sh`는 기본적으로 CLI의 기본 모델을 사용하며, 사용자가 override를 주지 않으면 버전명 하드코딩을 피합니다. 긴 프롬프트는 shell 인자로 직접 넘기지 않고 `docs/orchestration/external-cli/<task-id>/<plan-version>/<round>/` 아래의 Markdown request/response 파일로 왕복합니다. 이 명령은 review report를 만든 뒤 멈추며, 다음 `PLAN-v1.1`을 자동 생성하지 않습니다.

이 명령들은 스킬 사용의 본질이라기보다, 스킬의 운영 상태를 재현하거나 검증하기 위한 보조 인터페이스입니다.

## 프로젝트 구조

```text
codeguide/
├── README.md
├── README.en.md
├── SKILL.md
├── agents/
├── references/
├── scripts/
└── tests/
```

- `SKILL.md`: 운영 계약과 워크플로우 정책
- `agents/`: skill-facing agent 설정
- `references/`: 거버넌스, 아키텍처, 리뷰 기준 문서
- `scripts/`: 실제 실행 가능한 자동화 스크립트
- `tests/`: 쉘 도구 회귀 테스트

## 발전 과정

- 다른 스킬스 기술에 영감을 얻음
- 부트캠프 파이널 프로젝트에서 수동 마크다운 운영
- 컨텍스트 유실과 결정 사항 드리프트 반복 경험
- 반복 가능한 docs 라이프사이클용 쉘 스크립트로 정리
- supervising architect 모델 기반 multi-agent orchestration 규칙 추가
- 정합성, 최신성, secret hygiene 검증 게이트 추가
