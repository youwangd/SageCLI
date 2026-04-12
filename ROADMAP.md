# SageCLI — Roadmap & Competitive Intelligence

**Updated**: 2026-04-12 | **Repo**: github.com/youwangd/SageCLI | **Stars**: 1 | **Version**: 1.3.0

---

## Current State

SageCLI is a **5,808-line pure bash** AI agent orchestrator. 42 commands, 8 runtimes, 430 tests, CI on every push.

**What we ship that nobody else does in pure bash:**
- Runtime-agnostic orchestration (claude-code, cline, kiro, gemini-cli, codex, bash)
- Plan orchestrator with wave-based dependency execution
- Git worktree isolation per agent
- MCP server lifecycle management
- Skills system with registry support
- Inter-agent messaging + shared context
- Headless/CI mode with GitHub Action
- Agent guardrails (timeout, max-turns, retry)
- ACP protocol support
- Agent export/import (file + URL)
- Per-agent environment variables
- Agent chaining (`--then` pipelines)

---

## Competitive Landscape (April 2026)

### Star Tracker (from weekly intel 2026-04-11)

| Category | Project | Stars | Trend |
|----------|---------|------:|-------|
| Top Agents | opencode | 141K | Dominant |
| | cline | 60K | IDE-native, CLI 2.0 launched |
| | aider | 43K | Terminal pair programming |
| | goose | 41K | Multi-LLM extensible |
| Orchestrators | ruflo (ex claude-flow) | 31K | 🔥 +9.5K/wk, rebranded, added Codex |
| | gastown | 14K | Persistent work tracking |
| | claude-squad | 7K | tmux multi-agent |
| | emdash (YC W26) | 3.8K | 🆕 Funded parallel agent env |
| | aws/cli-agent-orchestrator | 451 | AWS official |
| Session Mgrs | nimbalyst (ex crystal) | 3K | Pivoted to desktop app |
| | toad | 2.8K | Unified terminal AI |
| | mux (Coder) | 1.6K | Desktop parallel dev |
| **Us** | **SageCLI** | **1** | Pure bash, zero-framework |

### Market Map

The space has three lanes:
1. **Session managers** (mux, claude-squad, toad) — run agents side-by-side
2. **Orchestrators** (ruflo, gastown, emdash) — coordinate multi-agent work
3. **Platform-native** (Claude Code Agent Teams, Copilot multi-file) — vendor lock-in

Sage sits at 1+2 with the unique angle of **zero dependencies** (bash/jq/tmux only). Every competitor requires Node.js, Python, Rust, or Go.

### Threat Assessment

| Threat | Level | Our Counter |
|--------|-------|-------------|
| Claude Code Agent Teams (official multi-agent) | HIGH | We orchestrate ANY runtime, not just Claude |
| ruflo 31K stars + Codex integration | HIGH | We already have 6 runtimes including Codex |
| emdash (YC-funded, 3.8K stars) | MEDIUM | We have more features, they have funding |
| Cline Kanban (visual task board) | MEDIUM | We're terminal-only — gap |
| Cline CLI 2.0 ("agent control plane") | MEDIUM | We already do this |

---

## Completed Phases (v1.0 → v1.3.0)

All shipped. Tests for each. CI green.

| Phase | What | Key Commands |
|-------|------|-------------|
| 0 | Testing foundation | 338 bats tests, CI, shellcheck, coverage |
| 1 | Git worktree isolation | `create --worktree`, `merge`, `diff` |
| 2 | Headless/CI mode | `send --headless --json`, `action.yml` |
| 3 | MCP tool integration | `mcp add/ls/rm`, `create --mcp` |
| 4 | Skills system | `skill install/ls/rm/show/run` |
| 5 | Memory & context sharing | `context set/get/ls/rm` |
| 6 | Sharing & portability | `export`, `create --from` (file + URL) |
| 7 | Observability | `history`, `info`, `stats`, `ls -l/--json` |
| 8 | Agent guardrails | `--timeout`, `--max-turns`, `--retry` |
| 9 | Per-agent environment | `env set/ls/rm`, `create --env` |
| 10 | Aggregate statistics | `stats`, `stats --json` |
| 11 | New runtimes | gemini-cli, codex (6 total) |
| — | Inter-agent messaging | `msg send/ls/clear`, auto-inject |
| — | Agent chaining | `send --then`, multi-step pipelines |
| — | Agent rename | `rename` |
| — | URL import | `create --from https://...` |

---

## Forward Roadmap

### Phase 12: Shell Completions & CLI Polish ← COMPLETE
**Use case**: "Tab-complete commands and agent names like docker/kubectl"

- [x] `sage completions bash` — bash tab-completion script
- [x] `sage completions zsh` — zsh tab-completion script
- [x] Completions cover: 42 subcommands, agent names, runtime names, skill/mcp/context/env/msg subcommands
- [x] Install via `eval "$(sage completions bash)"` or source from completion dir

### Phase 13: Adoption & Visibility
**Use case**: "People need to know sage exists"

This is the real bottleneck. 1 star with a feature-complete product = discovery problem.

- [ ] Get merged into [awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents) (PR #47 submitted)
- [ ] Record 2-minute demo GIF/asciinema for README (parallel multi-runtime audit use case)
- [ ] HN Show launch post — position as "pure bash, zero-framework agent orchestrator"
- [ ] r/ClaudeCode + r/LocalLLaMA posts with real use cases
- [ ] Submit to Tembo "AI Coding Agents Compared" list

### Phase 14: Swarm Patterns
**Use case**: "Fan out 5 agents to review code, fan in their findings"

This is ruflo's main draw (31K stars). Sage has `plan` for dependency waves but not named swarm patterns.

- [x] `sage plan --pattern fan-out` — spawn N agents with same task on different inputs, collect results
- [x] `sage plan --pattern pipeline` — chain agents sequentially (A→B→C), each transforms output
- [x] `sage plan --pattern debate` — N agents argue, synthesizer picks best answer
- [x] `sage plan --pattern map-reduce` — split work, parallel execute, merge results
- [x] Patterns are composable with existing plan YAML

### Phase 15: TUI Dashboard
**Use case**: "See all my agents, their status, and logs in one view"

Every orchestrator with >5K stars has visualization. Terminal-only is a differentiator but also a ceiling. Cline Kanban proves demand.

- [x] `sage dashboard` — live TUI with agent list, status, recent output
- [ ] Built with `gum` or `charmbracelet/bubbletea` (stays terminal-native, no web server)
- [x] Real-time log tailing per agent
- [x] Plan progress visualization (wave execution)
- [ ] Keyboard shortcuts: restart, stop, send task, view logs

### Phase 16: Persistent Sessions
**Use case**: "Reboot my machine, come back, agents resume where they left off"

gastown's main draw (14K stars). Sage agents die on reboot.

- [x] `sage create worker --persistent` — checkpoint agent state to disk
- [x] `sage restore` — resume all persistent agents after reboot
- [x] Plan execution survives restarts (plan --recover detects and resumes interrupted plans)
- [x] Session recovery: detect orphaned tmux sessions, offer to reclaim

### Phase 17: Local Model Support ← COMPLETE
**Use case**: "Run agents with ollama/llama.cpp, no cloud API needed"

Reddit signal: "I no longer need a cloud LLM to do quick web research." Small models (9B) hitting 89% workflow completion. Growing demand.

- [x] `sage create worker --runtime ollama` — local model runtime via ollama CLI
- [x] `sage create worker --runtime llama-cpp` — direct llama.cpp inference
- [x] Model selection: `--model qwen3:8b` or `--model llama3.2:3b`
- [x] Works with existing MCP/skills/context infrastructure

### Phase 18: Agent Observability v2
**Use case**: "How much did my agents cost? Which one is most efficient?"

- [ ] Token counting per agent (parse model output for usage stats)
- [ ] Cost estimation per runtime (configurable $/token rates)
- [ ] `sage stats --cost` — aggregate cost across agents
- [ ] `sage stats --efficiency` — tasks completed per dollar

---

## Killer Use Cases to Build Toward

1. **PR Review Pipeline**: `sage plan --pattern fan-out "Review PR #123"` → reviewer + security auditor + test writer in parallel → merge findings
2. **Codebase Migration**: `sage plan --pattern pipeline "Migrate Express→Fastify"` → spec → implement per-module → test → validate
3. **CI Agent**: GitHub Action runs `sage --headless` on every PR for automated review
4. **Oncall Triage**: `sage plan "Triage ticket T-12345"` → read ticket → check logs → propose fix → write tests
5. **Multi-Model Benchmark**: `sage plan --pattern debate "Implement auth"` → claude vs gemini vs codex → pick best implementation

---

## Competitor Signals (2026-04-11)

| Signal | Impact | Sage Status |
|--------|--------|-------------|
| ruflo 31K stars, Codex integration, enterprise features | HIGH | sage has 6 runtimes but 1 star — adoption gap |
| emdash (YC W26) 3.8K stars, funded | MEDIUM | sage has more features, they have money |
| Claude Code Agent Teams — official multi-agent | HIGH | sage works with ANY runtime, not just Claude |
| Claude Code Custom Subagents | MEDIUM | sage orchestrates across sessions (broader) |
| Cline CLI 2.0 "agent control plane" | MEDIUM | sage already does this |
| Cline Kanban visual task board | MEDIUM | sage is terminal-only (Phase 15 addresses) |
| AgentPipe inter-agent chat rooms | LOW | sage has `msg` commands ✅ |
| ACP in JetBrains + Zed | POSITIVE | validates sage's ACP investment ✅ |
| MCP Gateway pattern emerging | LOW | sage has `mcp` commands, gateway premature |
| mitchellh "hardware kill switch" (3.2K ❤️) | POSITIVE | sage has `--timeout` + `--max-turns` ✅ |
| Local models hitting 89% workflow completion | MEDIUM | Phase 17 addresses |
| "15 AI Coding Agents Compared" — sage not listed | HIGH | Phase 13 addresses |

---

## Monitoring

- **Weekly intel**: `sage-competitor-intel` cron (Mondays 12:00 UTC) → `/home/dyouwang/SageCLI/WEEKLY-INTEL.md`
- **Daily report**: `sagecli-daily-report` cron (14:00 UTC) → email
- **Self-improver**: `sage-improver` cron (hourly) → auto-ships features via TDD

*Next intel scan: 2026-04-13 (Monday)*
