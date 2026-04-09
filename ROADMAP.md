# SageCLI — Competitive Analysis & Self-Improvement Roadmap

**Date**: 2026-04-09 | **Repo**: github.com/youwangd/SageCLI | **Stars**: 1 | **Version**: 1.2.0

---

## Current State

SageCLI is a 3,530-line bash script that orchestrates AI coding agents via tmux. Key strengths:
- **Zero dependencies** beyond bash/jq/tmux — genuinely unique positioning
- **Runtime-agnostic** — supports Claude Code, Cline, ACP protocol, bash
- **Mechanical task tracking** — status transitions are code, not LLM behavior
- **Plan orchestrator** — dependency-aware wave execution with resume
- **ACP support** — persistent sessions, universal agent bridge
- **Security model** — name validation, workspace sandboxing, atomic writes

**Critical gap**: Zero tests. No CI. No automated quality gates.

---

## Competitive Landscape (April 2026)

### Direct Competitors (Orchestrators)
| Project | Stars | Approach | Sage's Edge |
|---------|-------|----------|-------------|
| claude-flow | 21.6K | Multi-agent swarms | Sage is runtime-agnostic, not Claude-only |
| gastown | 12.5K | Persistent work tracking | Sage has plan orchestrator with wave deps |
| Claude Squad | 6.4K | tmux session manager | Sage adds task tracking + orchestration |
| CLI Agent Orchestrator (AWS) | 330 | Hierarchical tmux delegation | Sage has ACP + plan system |
| ORCH | 9 | Typed task queue + state machine | Similar scope, Sage more mature |

### Adjacent (Session Managers)
| Project | Stars | What they do |
|---------|-------|-------------|
| cmux | 8.1K | Parallel agent sessions |
| Crystal | 3.0K | Parallel git worktrees |
| Toad | 2.7K | Parallel CLI sessions |

### Key Insight
The market has split into:
1. **Session managers** (cmux, Claude Squad) — run agents side-by-side
2. **Orchestrators** (claude-flow, gastown) — coordinate multi-agent work
3. **Infrastructure** (sandboxes, routers, browsers)

Sage sits at the intersection of 1+2 with the unique angle of being **pure bash, zero-framework**. This is a genuine differentiator — every competitor requires Node.js, Python, Rust, or Go.

---

## What Top Projects Do That Sage Doesn't

### From claude-flow (21.6K stars)
- Swarm patterns (fan-out/fan-in, pipeline, debate)
- Built-in memory/context sharing between agents
- Web dashboard for monitoring

### From gastown (12.5K stars)
- Persistent work tracking across sessions
- Git worktree isolation per agent
- Progress visualization

### From the awesome-cli-coding-agents list
- **Git worktree isolation** — Crystal, Catnip, vibe-tree all use this
- **Symbol-level locking** — Wit prevents merge conflicts via AST parsing
- **Headless/CI mode** — Cursor CLI, Junie CLI, Droid all support this
- **MCP integration** — Pi, Hermes, Kilo Code all have MCP support
- **Skills system** — Pi, Hermes, Roo Code, OpenClaw all have pluggable skills

---

## Improvement Roadmap (Test-Driven, Use-Case-First)

### Phase 0: Testing Foundation (MUST DO FIRST)
**Use case**: "I want to refactor sage without breaking anything"

- [ ] Create `tests/` directory with bats-core test framework
- [x] Unit tests for every command — 63 tests across 6 files (create/rm, ls/clean/status/inbox/send, tool/tasks/result/call/logs/trace, steer/peek/wait/attach/plan, CI)
- [ ] Integration tests: full lifecycle (create → send → wait → result)
- [x] CI via GitHub Actions (test on ubuntu + macos) — `.github/workflows/ci.yml`
- [x] Shellcheck linting on every PR — `--severity=error` in CI
- [x] Coverage tracking — `tests/coverage.sh` reports 80% command coverage (20/25), CI integrated

### Phase 1: Git Worktree Isolation
**Use case**: "Run 3 agents implementing different features in parallel without merge conflicts"

- [x] `sage create worker --worktree feature-auth` — auto-creates git worktree
- [x] Each agent works in isolated branch
- [x] `sage merge worker` — merges worktree back to main
- [x] Conflict detection before merge

### Phase 2: Headless/CI Mode
**Use case**: "Run sage in GitHub Actions to auto-review PRs"

- [x] `sage run --headless "Review this PR"` — no tmux required
- [x] JSON output mode for CI parsing — `--headless --json` outputs structured JSON
- [x] Exit codes for pass/fail — headless mode propagates handler exit code
- [x] GitHub Action wrapper — `action.yml` composite action at repo root

### Phase 3: MCP Tool Integration
**Use case**: "My agent can use any MCP server as a tool"

- [x] `sage create worker --mcp github,filesystem,browser`
- [ ] MCP server lifecycle management (start/stop with agent)
- [ ] Tool discovery and injection into agent prompts

### Phase 4: Skills System
**Use case**: "Community-contributed task templates and workflows"

- [ ] `sage skill install code-review-pro`
- [ ] Skills = task templates + tool configs + prompt engineering
- [ ] Skills registry (GitHub-based, like Homebrew taps)

### Phase 5: Memory & Context Sharing
**Use case**: "Agent B picks up where Agent A left off"

- [ ] Shared context store between agents (file-based, stays Unix-native)
- [ ] `sage context set key value` / `sage context get key`
- [ ] Auto-inject relevant context into agent prompts

---

## Killer Use Cases to Build Toward

1. **PR Review Pipeline**: `sage plan "Review PR #123"` → spawns reviewer + security auditor + test writer in parallel → merges findings
2. **Codebase Migration**: `sage plan "Migrate from Express to Fastify"` → spec → implement per-module → test → validate
3. **CI Agent**: GitHub Action that runs `sage --headless` on every PR for automated code review
4. **Oncall Triage**: `sage plan "Triage ticket T-12345"` → reads ticket → checks logs → proposes fix → writes tests

---

## Monitoring Competitors (Automated)

### What to track daily:
- New entries in awesome-cli-coding-agents (137 stars, 56 commits, active)
- Star counts of top 10 competitors
- New HN/Reddit posts about agent orchestration
- New ACP/MCP protocol developments

### What to learn from:
- Every project with >1K stars — read their README, understand their hook
- Every HN front-page agent post — what resonated, what got criticized
- Claude Code docs updates — they're the platform, we're the orchestrator
