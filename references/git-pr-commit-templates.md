# Git PR and Commit Templates

Use these templates when preparing pull requests and commits.

## PR description template

```markdown
## ✨ PR Summary
<!-- Summarize the purpose of this PR. -->


---

## 🔍 Background
<!-- Explain why this change is needed. -->
<!-- Include prior behavior, problem statement, or reproduction context. -->


---

## 🛠️ Changes
<!-- List the concrete changes made in this PR. -->
- 
- 
- 


---

## 🧠 Design Notes
<!-- Explain why this implementation approach was chosen. -->
<!-- Call out state transitions, logging policy, retry strategy, or similar details. -->


---

## 🧪 How to Test
<!-- Describe reproduction steps and validation commands. -->
1. 
2. 
3. 


---

## 📈 Expected Impact
<!-- Describe the expected product or engineering impact of this change. -->
- 
- 
- 


---

## ⚠️ Breaking Changes
<!-- Describe any changes that affect existing behavior. -->
- [ ] None
- [ ] Yes (details required)


---

## ✅ Checklist
- [ ] Builds successfully
- [ ] No repeated logs or unnecessary executions
- [ ] No sensitive information included
- [ ] Commit messages follow convention
- [ ] Documentation updated (if required)


---

## 🙋 Reviewer Notes
<!-- Call out areas that deserve focused reviewer attention. -->
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
