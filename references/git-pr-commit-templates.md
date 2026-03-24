# Git PR and Commit Templates

Use these templates when preparing pull requests and commits.

## PR description template

```markdown
## ✨ PR Summary
<!-- 이 PR의 목적을 간략히 설명하세요 -->


---

## 🔍 Background
<!-- 변경이 필요한 배경을 설명하세요 -->
<!-- 기존 동작 / 문제 상황 / 재현 방법 등 -->


---

## 🛠️ Changes
<!-- 실제 변경 사항을 항목으로 정리하세요 -->
- 
- 
- 


---

## 🧠 Design Notes
<!-- 왜 이런 방식으로 구현했는지 작성하세요 -->
<!-- 상태 전이, 로그 정책, 재시도 전략 등 -->


---

## 🧪 How to Test
<!-- 재현 및 검증 방법을 작성하세요 -->
1. 
2. 
3. 


---

## 📈 Expected Impact
<!-- 이번 변경의 기대 효과를 작성하세요 -->
- 
- 
- 


---

## ⚠️ Breaking Changes
<!-- 기존 동작에 영향을 주는 변경이 있다면 작성 -->
- [ ] None
- [ ] Yes (설명 필요)


---

## ✅ Checklist
- [ ] Builds successfully
- [ ] No repeated logs or unnecessary executions
- [ ] No sensitive information included
- [ ] Commit messages follow convention
- [ ] Documentation updated (if required)


---

## 🙋 Reviewer Notes
<!-- 리뷰어가 중점적으로 봐야 할 부분 -->
```

## Commit message template

```text
<type>: <short summary>

[optional detailed description]

- Why:
- What changed:
- Impact:

Refs: #
```

## Recommended commit types
- `feat`
- `fix`
- `refactor`
- `docs`
- `test`
- `chore`
- `perf`
- `ci`
