# Runtime Issue Tracker Contract

Use this reference before filing, fixing, verifying, closing, or reopening a runtime issue. A scaffolded project installs the authoritative operating artifact at `docs/issues/README.md`; this reference routes to that artifact rather than duplicating its procedural prose.

## Required operating rules

- Separate auditor and fixer roles: the auditor files defects and accepts verification; the fixer implements and records the resolution. A fixer never self-verifies.
- Follow the lifecycle file -> pick up -> fix -> verify -> close -> reopen. The generated `docs/issues/README.md` defines the required files, indexes, and close evidence at each transition.
- Keep the issue file and both indexes synchronized. A close pairs the moved issue with a resolution document and accepted running-stack verification; recurrence reopens the issue instead of deleting history.
- Use only these issue `status:` values: `open`, `investigating`, `blocked`, `fixed_pending_verify`, `resolved`, `reopened`.

## Authoritative project artifact

After scaffolding, read `<project-root>/docs/issues/README.md` and its linked templates before acting. It is the project-facing source of truth for lifecycle details; this skill-level reference is the navigation and minimum-contract home.
