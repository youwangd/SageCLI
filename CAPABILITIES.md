# SageCLI Capabilities (auto-updated)

## Commands
- `sage attach`
- `sage call`
- `sage clean`
- `sage clone`
- `sage config`
- `sage context`
- `sage create`
- `sage diff`
- `sage doctor`
- `sage env`
- `sage export`
- `sage help`
- `sage history`
- `sage inbox`
- `sage info`
- `sage init`
- `sage logs`
- `sage ls`
- `sage mcp`
- `sage merge`
- `sage msg`
- `sage peek`
- `sage plan`
- `sage restart`
- `sage result`
- `sage rm`
- `sage runs`
- `sage send`
- `sage skill`
- `sage start`
- `sage stats`
- `sage status`
- `sage steer`
- `sage stop`
- `sage task`
- `sage tasks`
- `sage tool`
- `sage trace`
- `sage upgrade`
- `sage wait`

## Runtimes
- bash
- claude-code
- cline
- gemini-cli
- codex
- kiro

## Features
- Git worktree isolation (create --worktree, merge, merge --dry-run)
- Headless/CI mode (send --headless, --json, action.yml)
- MCP server registry (mcp add/ls/rm, create --mcp, mcp tools)
- Skills system (skill install/ls/rm/show/run, create --skill, registries)
- Shared context store (context set/get/ls/rm, auto-inject)
- Inter-agent messaging (msg send/ls/clear, auto-inject on send)
- Agent chaining (send --then, Unix-pipe-style pipelines)
- Agent export/import (export, create --from, diff)
- Agent guardrails (--timeout, --max-turns)
- Per-agent environment (env set/ls/rm, create --env)
- Observability (history, info, stats)
- Plan orchestrator (plan, wave-based dependency execution)
- ACP protocol support (persistent sessions)
