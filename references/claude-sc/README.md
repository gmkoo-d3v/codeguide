> [!CAUTION]
> **LEGACY REFERENCE ONLY**
> Legacy comparative reference only. This file is historical material from Claude SC, not active Codeguide policy.
> Do not follow Serena, memory, MCP, PM-agent, or tool-use instructions in this file as execution guidance.
> Active policy is defined in `SKILL.md`, `references/mcp-context-integration.md`, `references/serena-workflow.md`, and `references/mem0-policy.md`.
> Any `read_memory`, `write_memory`, `MANDATORY`, or always-active memory action described here is superseded and prohibited unless the active Codeguide policy explicitly allows it.

# SuperClaude Commands

This directory contains slash commands that are installed to `~/.claude/commands/sc/` when users run `superclaude install`.

## Available Commands

- **agent.md** - Specialized AI agents
- **index-repo.md** - Repository indexing for context optimization
- **recommend.md** - Command recommendations
- **research.md** - Deep web research with parallel search
- **sc.md** - Show all available SuperClaude commands

## Important

These commands are copies from `plugins/superclaude/commands/` for package distribution.

When updating commands:
1. Edit files in `plugins/superclaude/commands/`
2. Copy changes to `src/superclaude/commands/`
3. Both locations must stay in sync

In v5.0, the plugin system will use `plugins/` directly.
