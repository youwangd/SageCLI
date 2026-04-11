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

- [x] Create `tests/` directory with bats-core test framework
- [x] Unit tests for every command — 63 tests across 6 files (create/rm, ls/clean/status/inbox/send, tool/tasks/result/call/logs/trace, steer/peek/wait/attach/plan, CI)
- [x] Integration tests: full lifecycle (create → send → result → rm) — 8 tests in sage-integration.bats
- [x] CI via GitHub Actions (test on ubuntu + macos) — `.github/workflows/ci.yml`
- [x] Shellcheck linting on every PR — `--severity=error` in CI
- [x] Coverage tracking — `tests/coverage.sh` reports 80% command coverage (20/25), CI integrated
- [x] 100% command coverage — start/stop/restart tests + fix stop silent crash bug (243 tests)

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
- [x] MCP server lifecycle management (start/stop with agent)
- [x] Tool discovery and injection into agent prompts

### Phase 4: Skills System
**Use case**: "Community-contributed task templates and workflows"

- [x] `sage skill install code-review-pro`
- [x] Skills = task templates + tool configs + prompt injection
- [x] Skills registry (GitHub-based, like Homebrew taps)

### Phase 5: Memory & Context Sharing
**Use case**: "Agent B picks up where Agent A left off"

- [x] Shared context store between agents (file-based, stays Unix-native)
- [x] `sage context set key value` / `sage context get key`
- [x] Auto-inject relevant context into agent prompts

---

## Phase 6: Sharing & Portability
**Use case**: "Share my agent setup with teammates or across machines"

- [x] `sage export <name>` — package agent config as shareable tar.gz
- [x] `sage create <name> --from <archive>` — import exported agent
- [x] `sage diff <name>` — show git changes in agent worktree
- [x] `sage export --format json` — JSON export for programmatic use

---

## Phase 7: Observability & Analytics
**Use case**: "What did my agents do today?"

- [x] `sage history` — agent activity timeline across all agents (--agent, -n, --json)
- [x] `sage info <name>` — full agent config and status view (--json)

---

## Phase 8: Agent Guardrails
**Use case**: "My agent ran for 3 hours and burned $50 — I need a kill switch"

- [x] `sage create worker --timeout 30m` — auto-kill agents after configurable duration (Nm/Nh/Ns)
- [x] `sage create worker --max-turns 50` — auto-stop agents after N task completions

---

## Phase 9: Agent Environment
**Use case**: "I need different API keys and configs for each agent"

- [x] `sage env set <agent> KEY=VALUE` — per-agent environment variables
- [x] `sage env ls <agent>` — list env vars (values masked)
- [x] `sage env rm <agent> KEY` — remove env var
- [x] `sage create worker --env KEY=VALUE` — set env vars at creation (repeatable)
- [x] Runner auto-loads env file before executing

---

## Phase 10: Aggregate Statistics
**Use case**: "What did my agents do today? How much compute time did I use?"

- [x] `sage stats` — aggregate metrics: agent counts, task counts, total runtime, most active agent
- [x] `sage stats --json` — JSON output for programmatic use

---

## Phase 11: New Runtime Handlers
**Use case**: "Orchestrate agents powered by any major AI CLI — not just Claude"

- [x] `sage create worker --runtime gemini-cli` — Google Gemini CLI runtime (headless -p, --yolo, GEMINI_SYSTEM_MD)
- [x] `sage create worker --runtime codex` — OpenAI Codex CLI runtime (exec mode)

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

## Competitor Signals (2026-04-11)

| Signal | Impact | Sage Status |
|--------|--------|-------------|
| claude-flow → ruflo rebrand, 31K stars (+9.5K/wk), added Codex integration | HIGH — fastest growing orchestrator | sage already has runtime-agnostic orchestration but lacks Codex runtime |
| emdash (YC W26) — 3.8K stars, open-source parallel agent dev env | MEDIUM — new funded competitor | sage already does parallel agents via plan + worktrees |
| Claude Code Agent Teams — official multi-agent orchestration | HIGH — platform-native reduces need for external tools | sage's edge: works with ANY runtime, not just Claude Code |
| Claude Code Custom Subagents — official subagent creation | MEDIUM — within-session only | sage orchestrates across sessions (broader scope) |
| Cline CLI 2.0 — terminal as "agent control plane" | MEDIUM — Cline has 60K star funnel | sage already has CLI orchestration |
| Cline Kanban — visual multi-agent task board | MEDIUM — demand for visual orchestration | sage is terminal-only (gap) |
| AgentPipe (98⭐) — inter-agent chat rooms | LOW — early stage | sage has context sharing but no real-time messaging (gap) |
| ACP in JetBrains + Zed — protocol adoption growing | POSITIVE — validates sage's ACP investment | sage already supports ACP ✅ |
| MCP Gateway pattern emerging — enterprise MCP infra | LOW (for now) — premature for sage | sage has mcp add/ls/rm ✅ |
| Gemini CLI (Google) — open-source terminal agent | MEDIUM — new runtime to support | sage doesn't have gemini-cli runtime (gap) |
| Codex $100 plan + 2X limits — rapid growth | HIGH — users will want to orchestrate Codex | sage doesn't have codex runtime (gap) |
| HN: "I still prefer MCP over skills" (262pts) — MCP vs skills debate | INFO — sage supports both | sage has mcp + skill commands ✅ |
| mitchellh: "need hardware kill switch for agents" (3.2K ❤️) | POSITIVE — validates sage's guardrails | sage has --timeout + --max-turns ✅ |

### Action Items
1. **[P0]** ~~Add Gemini CLI runtime handler~~ ✅ Done (Phase 11)
2. **[P0]** ~~Add Codex runtime handler~~ ✅ Done (Phase 11)
3. **[P0]** ~~Submit PR to awesome-cli-coding-agents to get listed~~ ✅ Done ([PR #47](https://github.com/bradAGI/awesome-cli-coding-agents/pull/47))
4. **[P1]** ~~Update README positioning: "orchestrate ANY agent" vs Claude-native teams~~ ✅ Done (c43433c)
5. **[P1]** Explore inter-agent messaging (beyond context sharing)
6. **[P2]** Consider lightweight web UI for plan visualization