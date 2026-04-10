# codeguide

영문 설명은 [README.en.md](./README.en.md)에서 볼 수 있습니다.

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

## 주요 기능

### 1. 워크스페이스 docs 스캐폴드 생성

[`scripts/init_docs_scaffold.sh`](./scripts/init_docs_scaffold.sh)는 idempotent한 docs 작업 공간을 생성합니다.

- `docs/task`
- `docs/shadow`
- `docs/decisions`
- `docs/plan`
- `docs/report`
- `docs/orchestration`

동시에 task, decision, review, orchestration 문서 템플릿도 함께 만듭니다.

### 2. docs gardening 자동화

[`scripts/doc_garden.sh`](./scripts/doc_garden.sh)는 task 문서와 decision 문서를 만들거나 갱신하면서, 기본적으로 이미 채워진 값을 빈 값으로 덮어쓰지 않도록 보호합니다.

주요 동작:

- `risk_level`을 task와 decision 문서에 함께 기록
- 실수로 빈 값으로 덮어쓰는 상황 방지
- delegated workflow용 orchestration 메타데이터 갱신
- 아키텍처 및 상태 동기화를 위한 shadow note 추가

### 3. 라이프사이클 실행기

[`scripts/run_codeguide.sh`](./scripts/run_codeguide.sh)는 작업 흐름의 메인 진입점입니다.

가능한 일:

- docs 라이프사이클 초기화
- task ID 추론 또는 명시 입력 처리
- task, decision, orchestration, shadow 기록 동기화
- `docs-only`와 `code-or-runtime` 경계 강제
- `code-or-runtime` 모드에서 allow-list 기반 런타임 명령 통제

### 4. 문서 검증

[`scripts/validate_docs.sh`](./scripts/validate_docs.sh)는 워크스페이스 문서를 `advisory` 또는 `strict` 모드로 검증합니다.

검증 항목:

- 필수 필드 존재 여부와 빈 값 여부
- 활성 task와 shadow 문서의 최신성
- 문서 길이 제한과 위생 규칙
- plan, review, orchestration 간 정합성
- 마크다운 문서의 secret pattern 스캔

### 5. 영어 문서 정책 검사

[`scripts/check_english_docs.sh`](./scripts/check_english_docs.sh)는 큐레이션된 마크다운 문서에서 한국어를 검사해, 내부 운영 문서를 영어 기준으로 유지하도록 돕습니다.

퍼블릭 진입점인 `README.md`는 한국어 메인 문서로 별도 운영합니다.

### 6. 회귀 테스트

[`tests/codeguide.bats`](./tests/codeguide.bats)는 다음 항목을 검증하는 Bats 기반 회귀 테스트를 제공합니다.

- overwrite protection
- task/decision synchronization
- orchestration bootstrapping
- strict validation failures
- secret scan edge cases
- workspace docs root behavior

## 사용 방법

먼저 루트를 한 번 설정합니다.

```bash
export CODEGUIDE_ROOT="$HOME/.codex/skills/codeguide"
```

워크스페이스 docs 스캐폴드를 초기화합니다.

```bash
"$CODEGUIDE_ROOT/scripts/init_docs_scaffold.sh" /path/to/project
```

작업 라이프사이클을 시작하거나 동기화합니다.

```bash
"$CODEGUIDE_ROOT/scripts/run_codeguide.sh" /path/to/project \
  --mode auto \
  --task-id search-nav-01 \
  --task-status in_progress \
  --shadow-note "search and navigation updated"
```

task와 decision 기록을 직접 생성하거나 갱신합니다.

```bash
"$CODEGUIDE_ROOT/scripts/doc_garden.sh" /path/to/project \
  --task-id search-nav-01 \
  --task-title "검색 및 내비게이션 흐름 정리" \
  --decision-id nav-structure-01 \
  --decision-title "docs-first 방식으로 내비게이션 변경 관리" \
  --risk-level medium
```

handoff 전이나 CI에서 문서를 검증합니다.

```bash
"$CODEGUIDE_ROOT/scripts/validate_docs.sh" /path/to/project --mode advisory
"$CODEGUIDE_ROOT/scripts/validate_docs.sh" /path/to/project --mode strict
```

영어 운영 문서 정책을 확인합니다.

```bash
"$CODEGUIDE_ROOT/scripts/check_english_docs.sh" "$CODEGUIDE_ROOT"
```

회귀 테스트를 실행합니다.

```bash
bats "$CODEGUIDE_ROOT/tests/codeguide.bats"
```

## 예시 워크플로우

1. 프로젝트용 `../docs`를 초기화합니다.
2. `run_codeguide.sh`로 task를 시작합니다.
3. `doc_garden.sh`로 task와 decision 맥락을 기록합니다.
4. Plan Ping-Pong Loop 동안 plan과 review 문서를 유지합니다.
5. 구조적 변경이 생길 때 shadow와 orchestration 문서를 다시 동기화합니다.
6. handoff 전에 `validate_docs.sh`를 실행합니다.
7. 마지막에 `--task-status done`으로 라이프사이클을 닫습니다.

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

- 부트캠프 파이널 프로젝트에서 수동 마크다운 운영
- 컨텍스트 유실과 결정 사항 드리프트 반복 경험
- 반복 가능한 docs 라이프사이클용 쉘 스크립트로 정리
- supervising architect 모델 기반 multi-agent orchestration 규칙 추가
- 정합성, 최신성, secret hygiene 검증 게이트 추가

## 이 저장소가 포트폴리오에서 의미 있는 이유

이 저장소는 CRUD 예제나 단발성 프로젝트 결과물이 아닙니다.

LLM 보조 개발을 어떻게 구조화할지에 대한 개인적인 엔지니어링 워크플로우 자산에 가깝습니다.

- 결정을 명시적으로 남기고
- 활성 작업과 현재 시스템 상태를 분리하고
- 계획을 검토 가능한 형태로 유지하고
- 컨텍스트 잡음을 줄이고
- 문서와 실행에 품질 게이트를 붙이는 방식
