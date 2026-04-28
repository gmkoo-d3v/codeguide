---
name: git
description: "Git operations with intelligent commit messages and workflow optimization"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

> [!CAUTION]
> **LEGACY REFERENCE ONLY**
> Legacy comparative reference only. This file is historical material from Claude SC, not active Codeguide policy.
> Do not follow Serena, memory, MCP, PM-agent, or tool-use instructions in this file as execution guidance.
> Active policy is defined in `SKILL.md`, `references/mcp-context-integration.md`, `references/serena-workflow.md`, and `references/mem0-policy.md`.
> Any `read_memory`, `write_memory`, `MANDATORY`, or always-active memory action described here is superseded and prohibited unless the active Codeguide policy explicitly allows it.


# /sc:git - Git Operations

## Triggers
- Git repository operations: status, add, commit, push, pull, branch
- Need for intelligent commit message generation
- Repository workflow optimization requests
- Branch management and merge operations

## Usage
```
/sc:git [operation] [args] [--smart-commit] [--interactive]
```

## Behavioral Flow
1. **Analyze**: Check repository state and working directory changes
2. **Validate**: Ensure operation is appropriate for current Git context
3. **Execute**: Run Git command with intelligent automation
4. **Optimize**: Apply smart commit messages and workflow patterns
5. **Report**: Provide status and next steps guidance

Key behaviors:
- Generate conventional commit messages based on change analysis
- Apply consistent branch naming conventions
- Handle merge conflicts with guided resolution
- Provide clear status summaries and workflow recommendations

## Tool Coordination
- **Bash**: Git command execution and repository operations
- **Read**: Repository state analysis and configuration review
- **Grep**: Log parsing and status analysis
- **Write**: Commit message generation and documentation

## Key Patterns
- **Smart Commits**: Analyze changes → generate conventional commit message
- **Status Analysis**: Repository state → actionable recommendations
- **Branch Strategy**: Consistent naming and workflow enforcement
- **Error Recovery**: Conflict resolution and state restoration guidance

## Examples

### Smart Status Analysis
```
/sc:git status
# Analyzes repository state with change summary
# Provides next steps and workflow recommendations
```

### Intelligent Commit
```
/sc:git commit --smart-commit
# Generates conventional commit message from change analysis
# Applies best practices and consistent formatting
```

### Interactive Operations
```
/sc:git merge feature-branch --interactive
# Guided merge with conflict resolution assistance
```

## Boundaries

**Will:**
- Execute Git operations with intelligent automation
- Generate conventional commit messages from change analysis
- Provide workflow optimization and best practice guidance

**Will Not:**
- Modify repository configuration without explicit authorization
- Execute destructive operations without confirmation
- Handle complex merges requiring manual intervention