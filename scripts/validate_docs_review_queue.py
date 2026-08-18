import sys

path = sys.argv[1]
candidates = {}
questions = []
section = ""
current = None
current_kind = ""

def flush():
    global current
    if not current:
        return
    if current_kind == "candidate":
        candidates[current.get("id", "")] = dict(current)
    elif current_kind == "question":
        questions.append(dict(current))
    current = None

with open(path, encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if line == "## Evidence Candidates":
            flush()
            section = "candidates"
            continue
        if line == "## Review Questions":
            flush()
            section = "questions"
            continue
        if line.startswith("## "):
            flush()
            section = ""
            continue
        if line.startswith("- id: ") and section in {"candidates", "questions"}:
            flush()
            current_kind = "candidate" if section == "candidates" else "question"
            current = {"id": line.split(":", 1)[1].strip()}
            continue
        if current is not None and line.startswith("  ") and ":" in line:
            key, value = line.strip().split(":", 1)
            current[key.strip()] = value.strip()
flush()

issues = []
for candidate_id, candidate in candidates.items():
    if candidate.get("source_ref") == "unknown" and candidate.get("question_state") != "deferred_missing_context":
        issues.append(f"candidate {candidate_id}: unknown source_ref requires question_state deferred_missing_context")
for question in questions:
    ref = question.get("evidence_ref", "")
    candidate = candidates.get(ref)
    if not candidate:
        issues.append(f"question {question.get('id', '<unknown>')}: evidence_ref does not resolve to candidate {ref}")
        continue
    if candidate.get("source_ref") == "unknown" or candidate.get("question_state") == "deferred_missing_context":
        issues.append(f"question {question.get('id', '<unknown>')}: must not ask about deferred or unknown-source candidate {ref}")
for issue in issues:
    print(issue)
