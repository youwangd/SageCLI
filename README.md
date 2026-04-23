<p align="center">
  <img src="logo.png" alt="sage" width="160" height="160">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/bash-4.0+-4EAA25?logo=gnubash&logoColor=white" alt="Bash 4.0+">
  <img src="https://img.shields.io/badge/jq-1.6+-CB171E?logo=jq&logoColor=white" alt="jq 1.6+">
  <img src="https://img.shields.io/badge/tmux-3.0+-1BB91F?logo=tmux&logoColor=white" alt="tmux 3.0+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <br>
  <img src="https://img.shields.io/badge/Claude_Code-supported-7C3AED?logo=anthropic&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/Gemini_CLI-supported-4285F4?logo=google&logoColor=white" alt="Gemini CLI">
  <img src="https://img.shields.io/badge/Codex-supported-412991?logo=openai&logoColor=white" alt="Codex">
  <img src="https://img.shields.io/badge/Cline-supported-F97316?logo=data:image/svg%2bxml;base64,PHN2ZyBmaWxsPSJ3aGl0ZSIgcm9sZT0iaW1nIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0ibTIzLjM2NSAxMy41NTYtMS40NDItMi44OTVWOC45OTRjMC0yLjc2NC0yLjIxOC01LjAwMi00Ljk1NC01LjAwMmgtMi40NjRjLjE3OC0uMzY3LjI3Ni0uNzc5LjI3Ni0xLjIxM0EyLjc3IDIuNzcgMCAwIDAgMTIuMDE4IDBhMi43NyAyLjc3IDAgMCAwLTIuNzYzIDIuNzc5YzAgLjQzNC4wOTguODQ2LjI3NiAxLjIxM0g3LjA2N2MtMi43MzYgMC00Ljk1NCAyLjIzOC00Ljk1NCA1LjAwMnYxLjY2N0wuNjQgMTMuNTQ5Yy0uMTQ5LjI5LS4xNDkuNjM2IDAgLjkyN2wxLjQ3MiAyLjg1NXYxLjY2N0MyLjExMyAyMS43NjIgNC4zMyAyNCA3LjA2NyAyNGg5LjkwMmMyLjczNiAwIDQuOTU0LTIuMjM4IDQuOTU0LTUuMDAyVjE3LjMzbDEuNDQtMi44NjVjLjE0My0uMjg2LjE0My0uNjIyLjAwMi0uOTFtLTEyLjg1NCAyLjM2YTIuMjcgMi4yNyAwIDAgMS0yLjI2MSAyLjI3MyAyLjI3IDIuMjcgMCAwIDEtMi4yNjEtMi4yNzN2LTQuMDQyQTIuMjcgMi4yNyAwIDAgMSA4LjI0OSA5LjZhMi4yNjcgMi4yNjcgMCAwIDEgMi4yNjIgMi4yNzR6bTcuMjg1IDBhMi4yNyAyLjI3IDAgMCAxLTIuMjYgMi4yNzMgMi4yNyAyLjI3IDAgMCAxLTIuMjYyLTIuMjczdi00LjA0MkEyLjI2NyAyLjI2NyAwIDAgMSAxNS41MzUgOS42YTIuMjY3IDIuMjY3IDAgMCAxIDIuMjYxIDIuMjc0eiIvPjwvc3ZnPg==" alt="Cline">
  <img src="https://img.shields.io/badge/Kiro-supported-FF6B35" alt="Kiro">
  <img src="https://img.shields.io/badge/Bash-supported-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
</p>

<h1 align="center">⚡ sage</h1>
<h3 align="center">Simple Agent Engine</h3>

<p align="center">
  <strong>Orchestrate AI coding agents from your terminal.</strong><br>
  No frameworks. No npm. No Python. Just bash, jq, and tmux.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#why-sage">Why sage?</a> •
  <a href="#use-cases">Use Cases</a> •
  <a href="#live-monitoring">Live Monitoring</a> •
  <a href="#commands">Commands</a> •
  <a href="DEVELOPMENT.md">Development</a>
</p>

<p align="center">
  <img src="docs/demo.gif" alt="sage demo" width="800">
</p>

---

## Why sage?

Every AI coding agent framework wants you to learn a new language, install a runtime, and buy into an ecosystem. sage takes a different approach:

**Agents are processes. Messages are files. The terminal is your IDE.**

```bash
sage create reviewer --runtime claude-code
sage create auditor --runtime kiro
sage send --headless --json reviewer "Review src/main.py for bugs"
sage send --headless --json auditor "Security audit src/main.py"
# Both run in parallel. Structured JSON output. Any runtime.
```

### The Numbers

| Metric | Value |
|--------|-------|
| Lines of code | ~8,500 (single bash script) |
| Dependencies | 3 (`bash`, `jq`, `tmux`) |
| Runtimes | 8 (Claude Code, Gemini CLI, Codex, Cline, Kiro, Bash, Ollama, llama.cpp) + any ACP agent |
| Commands | 53 |
| Tests | 928 (bats-core, CI on ubuntu + macOS) |
| Install time | < 10 seconds |

### What Makes sage Different

Every competitor requires Node.js, Python, Rust, or Go. sage requires bash.

| | sage | claude-flow | gastown | Claude Squad |
|---|---|---|---|---|
| Language | bash | TypeScript | TypeScript | Go |
| Dependencies | jq + tmux | Node.js + npm | Node.js + npm | Go runtime |
| Runtimes | 8 native + ACP | Claude only | Claude only | Claude only |
| Headless/CI | ✅ `--headless --json` | ❌ | ❌ | ❌ |
| Git worktrees | ✅ built-in | ❌ | ✅ | ❌ |
| MCP support | ✅ registry + lifecycle | ✅ | ❌ | ❌ |
| Skills system | ✅ install + registries | ❌ | ❌ | ❌ |

### Design Principles

- **Unix-native** — Agents are tmux windows. Messages are JSON files in directories. No daemons, no databases, no Docker.
- **Runtime-agnostic** — Plug in Claude Code, Gemini CLI, Codex, Cline, Kiro, Ollama, llama.cpp, Bash, or any ACP agent. Adding a new runtime is one file with two functions.
- **Mechanical, not behavioral** — Task tracking, parent-child relationships, and tracing are handled by the engine, not by asking LLMs to remember protocols.
- **Observable** — Real-time streaming, `peek` into any agent, `trace` the full call tree. You always know what's happening.
- **Secure by default** — Agent name validation, workspace sandboxing for file I/O, atomic writes to prevent partial reads, and path traversal prevention at every layer.
- **Zero lock-in** — It's a single bash script. Read it, fork it, modify it. Your agents' state is plain files on disk.

---

## Install

**Homebrew** (macOS & Linux):
```bash
brew tap youwangd/sage
brew install sage
```

**npm** (cross-platform):
```bash
npm install -g @youwangd/sage
```

**curl** (one-liner):
```bash
curl -fsSL https://raw.githubusercontent.com/youwangd/SageCLI/main/install.sh | bash
```

**Manual:**
```bash
git clone https://github.com/youwangd/SageCLI.git
cd SageCLI
ln -s $(pwd)/sage ~/bin/sage    # or /usr/local/bin/sage
sage init
```

**Requirements:** `bash` 4.0+, `jq` 1.6+, `tmux` 3.0+

**Optional runtimes:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Codex CLI](https://github.com/openai/codex), [Cline CLI](https://github.com/cline/cline), or any [ACP-compatible agent](https://agentclientprotocol.com/get-started/agents)

---

## Quick Start

```bash
# Create an agent and give it work
sage create worker --runtime claude-code
sage send worker "Build a Python CLI that converts CSV to JSON"

# Watch it work
sage peek worker          # live tool calls + output
sage attach worker        # full tmux terminal access

# Get the result
sage tasks worker         # task status + elapsed time
sage result <task-id>     # structured output
```

`sage start` is optional — `send` and `call` auto-start agents that aren't running.

Messages can be inline text or loaded from files:

```bash
sage send worker "Quick task"               # inline
sage send worker @prompt.md                 # from file
sage send worker @~/tasks/big-project.md    # ~ expansion supported
```

---

## Use Cases

### 🔥 Parallel Multi-Runtime Security Audit (Verified)

Run different AI agents on the same code simultaneously, each in an isolated git branch:

```bash
# Create two agents with different runtimes, each in their own worktree
sage create reviewer --worktree review-branch --runtime claude-code
sage create auditor --worktree audit-branch --runtime kiro

# Fire both in parallel
sage send --headless --json reviewer "Review cmd_send() for bugs" &
sage send --headless --json auditor "Security audit cmd_send()" &
wait

# Results:
# reviewer (Claude Code, 12s): Found 3 bugs — unsafe ls parsing, missing error handling
# auditor  (Kiro, 41s):        Found 6 issues — path traversal, command injection, unsafe glob
# Wall time: 41s (parallel), not 53s (sequential)
```

### ⚡ Headless CI Mode (Verified)

Run sage in GitHub Actions — no tmux, no terminal, structured JSON output:

```bash
sage send --headless --json reviewer "Is this safe? eval(\$user_input)"
```
```json
{
  "status": "done",
  "task_id": "headless-1775793946",
  "exit_code": 0,
  "elapsed": 34,
  "output": "UNSAFE. eval \"$user_input\" is a critical command injection vulnerability..."
}
```

Use the included GitHub Action:
```yaml
- uses: youwangd/SageCLI@main
  with:
    runtime: claude-code
    task: "Review this PR for security issues"
```

### 🌐 8 Runtimes, One Interface (Verified)

Same command, any AI backend:

```bash
sage create a1 --runtime claude-code   # Anthropic Claude (Bedrock)
sage create a2 --runtime gemini-cli    # Google Gemini
sage create a3 --runtime codex         # OpenAI Codex (via LiteLLM)
sage create a4 --runtime cline         # Cline (configurable)
sage create a5 --runtime kiro          # Kiro (Bedrock)
sage create a6 --runtime bash          # Custom scripts

# All use the same interface:
sage send --headless --json a1 "Review this code"
sage send --headless --json a2 "Review this code"
# ... identical JSON output format regardless of runtime
```

### 🏗️ Plan Orchestrator with Wave Execution

Decompose complex goals into dependency-aware parallel waves:

```bash
sage plan "Build a Python REST API with auth, CRUD, tests, and docs"

#  Wave 1: #1 Define API schema (sequential)
#  Wave 2: #2 Build auth + #3 Build CRUD (parallel)
#  Wave 3: #4 Write tests + #5 Generate docs (parallel)
```

### 🔧 MCP + Skills Ecosystem

```bash
# Register MCP servers
sage mcp add github --command "npx" --args "@modelcontextprotocol/server-github"
sage create dev --runtime claude-code --mcp github

# Install community skills
sage skill install https://github.com/user/code-review-skill
sage create reviewer --runtime claude-code --skill code-review-pro

# Skills inject system prompts + tool configs automatically
sage send reviewer "Review PR #42"
```

### 🛡️ Agent Guardrails

```bash
# Auto-kill after 30 minutes
sage create worker --runtime claude-code --timeout 30m

# Stop after 50 task completions
sage create worker --runtime claude-code --max-turns 50

# Per-agent environment isolation
sage env set worker API_KEY=sk-xxx
sage env set worker DATABASE_URL=postgres://...
```

---

## Task Templates

Predefined task templates with checklists, constraints, and structured output:

```bash
sage task --list
#  review       (auto)  Code review with prioritized findings
#  test         (auto)  Generate comprehensive test suite
#  spec         (auto)  Write technical specification
#  implement    (auto)  Implement a feature from spec
#  refactor     (auto)  Refactor code while preserving behavior
#  document     (auto)  Generate documentation
#  debug        (auto)  Debug and fix a reported issue

# Run a template against files
sage task review src/auth.py src/middleware.py
sage task test src/api/ --message "Focus on edge cases"
sage task refactor src/legacy.py --timeout 180
sage task debug --message "Users report 500 on /login after upgrade"
```

Templates live in `~/.sage/tasks/` as markdown files with YAML frontmatter. Each template specifies:
- Runtime preference (`auto` defaults to ACP)
- Input type (`files`, `description`, or `both`)
- A detailed checklist the agent follows

Run in background with `--background`:
```bash
sage task implement --message "Add JWT refresh tokens" --background
# ✓ task t-123 → sage-task-implement-... (background)
# Track: sage peek sage-task-implement-... | sage result t-123
```

---

## Plan Orchestrator

<p align="center">
  <img src="docs/diagrams/plan-waves.svg" alt="Plan orchestrator — dependency waves with parallel execution" width="780">
</p>

Decompose complex goals into dependency-aware task waves with automatic parallel execution:

```bash
sage plan "Build a Python REST API with auth, CRUD endpoints, tests, and docs"

#  📋 Plan: Build a Python REST API...
#
#  #1 [spec] Define API schema and auth strategy
#  #2 [implement] Build auth module (depends: #1)
#  #3 [implement] Build CRUD endpoints (depends: #1)
#  #4 [test] Write test suite (depends: #2, #3)
#  #5 [document] Generate API docs (depends: #2, #3)
#
#  Waves:
#    Wave 1: #1
#    Wave 2: #2, #3 (parallel)
#    Wave 3: #4, #5 (parallel)
#
#  [a]pprove  [e]dit  [r]eject
```

The plan orchestrator:
1. Creates a planning agent to decompose your goal
2. Normalizes the output (handles different JSON formats from different LLMs)
3. Computes dependency waves with cycle detection
4. Executes each wave in parallel — agents in the same wave run simultaneously
5. Passes results from completed tasks as context to downstream dependencies

```bash
# Auto-approve (skip interactive prompt)
sage plan "Refactor auth module to use OAuth2" --yes

# Save plan for later
sage plan "Migrate database" --save migration.json

# Run a saved plan
sage plan --run migration.json

# Resume from where it left off (skips completed tasks)
sage plan --resume ~/.sage/plans/plan-1710347041.json

# List saved plans
sage plan --list

# Interactive editing before execution
sage plan "Build a dashboard"
# > edit> drop 3
# > edit> add test "Integration tests for API" --depends 1,2
# > edit> done
```

---

## Live Monitoring

Both CLI runtimes stream events in real-time. Tool calls, text responses, and progress appear as they happen:

```bash
sage peek master --lines 20
```

```
 ⚡ peek: master

 Live output:
   I'll create a professional restaurant template with modern design...

 Runner log:
   [22:15:28] master: invoking claude-code...
   I'll create a professional restaurant template...
     → ToolSearch
     → TodoWrite
     → Write
     → TodoWrite
     → Write

 Workspace: 4 file(s)
   22:17  19889  styles.css
   22:16  23212  index.html
```

`sage attach` drops you into the tmux session for full terminal access.

---

## Task Tracking

Every task gets a trackable ID. Status transitions are mechanical — no LLM behavior dependency.

```
queued → running → done
```

```bash
sage send worker "Build the entire app"
# ✓ task t-1710347041 → worker

sage tasks worker
#  TASK              AGENT   STATUS   ELAPSED  FROM
#  t-1710347041      worker  running  45s      cli

sage result t-1710347041     # structured output when done
sage wait worker             # block until agent finishes
```

---

## Tracing

Full observability into how agents collaborate:

```bash
# Timeline
sage trace
#  17:00:40  send   cli → orch      "Build the app..."
#  17:01:02  send   orch → sub1     "Write fibonacci..."
#  17:01:20  done   sub1 ✓          18s
#  17:02:08  done   orch ✓          88s

# Call hierarchy
sage trace --tree
#  t-123 cli → orch "Build the app" (88s) ✓
#    ├─ t-456 orch → sub1 "Write fibonacci..." (18s) ✓
#    └─ t-789 orch → sub2 "Write factorial..." (16s) ✓

# Filter
sage trace orch              # events for one agent
sage trace --tree -n 50      # last 50 events as tree
```

---

## Runtimes

| Runtime | Backend | Streaming | How it works |
|---|---|---|---|
| `claude-code` | [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | ✅ stream-json | Real-time tool calls + text via `--output-format stream-json` |
| `gemini-cli` | [Gemini CLI](https://github.com/google-gemini/gemini-cli) | ✅ json | Headless mode via `-p`, supports `--yolo` for auto-approve |
| `codex` | [Codex CLI](https://github.com/openai/codex) | — | Exec mode with auto-approve |
| `cline` | [Cline CLI](https://github.com/cline/cline) | ✅ json | Real-time events via `--json` |
| `kiro` | [Kiro](https://kiro.dev) | ✅ json | Amazon's agent IDE, headless via `kiro-cli chat` |
| `ollama` | [Ollama](https://ollama.com) | ✅ tokens | Local models (qwen3, llama3.2, etc.) via `ollama run` |
| `llama-cpp` | [llama.cpp](https://github.com/ggerganov/llama.cpp) | ✅ tokens | Direct inference against `llama-cli` / GGUF models |
| `acp` | [Agent Client Protocol](https://agentclientprotocol.com) | ✅ JSON-RPC | Universal bridge — any ACP agent via stdio. Persistent sessions with live steering. |
| `bash` | Shell script | — | Custom `handler.sh` processes messages |

The `acp` runtime speaks JSON-RPC 2.0 over stdio and works with **any** ACP-compatible agent:

```bash
sage create worker --agent cline         # Cline via ACP
sage create worker --agent claude-code   # Claude Code via ACP (needs claude-agent-acp adapter)
sage create worker --agent goose         # Goose via ACP
sage create worker --agent kiro          # Kiro via ACP
sage create worker --agent gemini        # Gemini CLI via ACP
```

Unlike the dedicated `cline`/`claude-code` runtimes (one-shot per task), ACP maintains a **persistent session** — follow-up messages go into the same conversation, enabling true live steering.

Adding a runtime is one file with two functions (`runtime_start` + `runtime_inject`). See [DEVELOPMENT.md](DEVELOPMENT.md).

### Local model benchmark (CPU-only)

Three `ollama` agents running `llama3.2:3b` in parallel on a **16-core Xeon, 62 GB RAM, no GPU**:

| Metric | Value |
|--------|-------|
| 3 parallel `sage send` round-trip | **34 s** end-to-end |
| Raw ollama throughput | 13.81 tok/s gen · 23.67 tok/s prompt eval |
| Peak CPU / RAM | 75 % (1 core-saturated ollama) · ~2.4 GB resident |
| Framework overhead | ~8500 lines of bash, no Python/Node/Go |

Ollama serializes generation on a single model instance — set `OLLAMA_NUM_PARALLEL=3` or run multiple instances for true inference parallelism. See the [r/LocalLLaMA write-up](https://www.reddit.com/r/LocalLLaMA/comments/1stvezm/).

---

## Architecture

<p align="center">
  <img src="docs/diagrams/architecture.svg" alt="SageCLI message lifecycle: User → sage send → inbox → runner.sh → runtime shim → LLM → results" width="820">
</p>

```
sage CLI
  │
  ├─ sage create <name>    → ~/.sage/agents/<name>/{inbox,workspace,results}
  ├─ sage send <name> msg  → writes JSON to inbox/, auto-starts if needed
  │
  └─ runner.sh (per agent, in tmux window)
       ├─ polls inbox/ every 300ms
       ├─ sources runtimes/<runtime>.sh
       ├─ calls runtime_inject() per message
       ├─ streams events to tmux pane (live monitoring)
       └─ writes task status + results mechanically
```

**Everything is a file:**

```
~/.sage/
├── agents/<name>/
│   ├── inbox/          # incoming messages
│   ├── workspace/      # agent's working directory
│   ├── results/        # task status + output
│   ├── steer.md        # steering context
│   └── .live_output    # current task's live output
├── runtimes/           # bash, claude-code, cline, codex, gemini-cli, kiro, ollama, llama-cpp, acp
├── tools/              # shared utilities
├── tasks/              # task templates (review, test, spec, ...)
├── plans/              # saved execution plans
├── trace.jsonl         # append-only event log
└── runner.sh           # agent process loop
```

---

## Commands

53 commands across 12 domains. Run `sage help` or `sage <command> --help` for full reference.

```
AGENTS
  init [--force]                 Initialize ~/.sage/
  demo [--clean]                 Scaffold a 3-agent fan-out demo
  create <name> [flags]          Create agent (--runtime R, --agent A, --model M)
  start   [name|--all]           Start in tmux
  stop    [name|--all]           Stop (kills process group)
  restart [name|--all]           Restart
  status  [--json]               Tree view of agents
  ls                             List agents (-l, --json, --running, --stopped, --runtime, --sort)
  info <name>                    Show full agent configuration and status
  rename <old> <new>             Rename an agent
  clone <src> <dest>             Duplicate config (no state)
  diff <name|--all> [--stat]     Git changes in agent worktree(s)
  merge <name> [--dry-run]       Merge worktree branch back to parent
  export <name> [--output f]     Archive as tar.gz (or --format json)
  rm <name>                      Remove agent
  clean                          Remove stale files

MESSAGING & TASKS
  send <to> <msg|@file> [flags]  Fire-and-forget (--force, --then <agent> for chains)
  call <to> <msg|@file> [secs]   Synchronous request/response
  tasks [name]                   List tasks (--json, --status)
  runs                           List active runs
  result <task-id>               Get task result
  replay [task-id]               Re-send a previous task
  wait <name|--all>              Wait for completion (--timeout N)
  peek <name> [--lines N]        Live tmux pane + workspace view
  steer <name> <msg> [--restart] Course-correct a running agent
  inbox [--json] [--clear]       Messages sent TO the CLI

PLAN ORCHESTRATOR
  plan <goal>                    Decompose a goal into dependency waves
  plan --pattern <p>             Swarm pattern: fan-out | pipeline | debate | map-reduce
  plan --run <file>              Execute a saved plan
  plan --resume <file>           Resume from failure point
  plan --recover                 Detect and resume interrupted plans
  plan --validate <file>         Validate YAML/JSON without executing
  plan --list                    Show saved plans

TASK TEMPLATES
  task --list                    Show available templates (review, test, spec, debug, ...)
  task <template> [files...]     Run a template (--message, --runtime, --timeout, --background)

MCP + SKILLS + TOOLS
  mcp {add|ls|rm|tools}          Register MCP servers with lifecycle management
  skill {install|ls|rm|show|run} Install from URL/path/registry; auto-injects prompts
  tool {add|ls|rm|run|show}      Local-tool registry per agent

ACP REGISTRY
  acp ls [--json]                List agents in the ACP Registry
  acp show <id>                  Show agent metadata (distribution, description)
  acp install <id> [--as name]   Install an ACP-registry agent as a sage agent

MEMORY & CONTEXT & ENV
  memory {set|get|ls|rm|clear} <agent> [k] [v]   Per-agent persistent memory (auto-injected)
  context {set|get|ls|rm} [k] [v]                Shared context across all agents
  env {set|ls|rm|scope} <agent> [k] [v]          Per-agent environment variables

OBSERVABILITY
  stats [--json] [--agent N]     Aggregate or per-agent metrics (--since, --cost, --efficiency)
  logs <name> [-f|--clear]       View/tail/clear logs (also --all, --failed)
  trace [name] [--tree] [-n N]   Cross-agent interaction timeline + call hierarchy
  history [--agent a] [-n N]     Activity timeline (--prune, --json)
  dashboard [--json|--live]      Live TUI: status, log tailing, plan progress

LIFECYCLE & RECOVERY
  checkpoint <name|--all>        Save agent state to disk
  restore    [name|--all]        Resume agents after reboot
  recover    [--yes]             Fix orphaned/dead tmux sessions
  doctor     [--all|--security|--agents|--mcp] [--json]   Health check

INTER-AGENT MESSAGING
  msg {send|ls|clear} <from> <to>  Inter-agent messages (auto-injected into prompts)

PRODUCTIVITY
  alias {set|ls|rm} <n> [cmd]    Reusable command shortcuts
  config {set|get|ls|rm}         Persistent user defaults
  watch <dir> --agent <n>        File watcher: trigger agent on changes
  completions <bash|zsh>         Generate tab-completion scripts
  attach [name]                  Attach to tmux session directly
  upgrade [--check]              Self-update from GitHub
  version | help                 Self-explanatory
```

## Configuration

Agents are configured via `runtime.json`:

```json
{
  "runtime": "claude-code",
  "model": "claude-sonnet-4-6",
  "parent": "orch",
  "workdir": "/path/to/project",
  "created": "2026-03-13T22:00:00Z"
}
```

Customize agent behavior by editing `instructions.md` in the agent directory.

---

## Contributing

sage is a single bash script. Read it, understand it, improve it.

```bash
wc -l sage    # ~8,500 lines

# Run tests
bats tests/   # 928 tests across 155 files

# Run from source
./sage init --force
./sage create test --runtime bash
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details, runtime interface, and how to add new runtimes.

---

## Roadmap

**v1.0 → v1.3.0 shipped.** Phases 0–19 complete: testing foundation, git worktree isolation, headless/CI mode, MCP + skills systems, inter-agent messaging, shared context, export/import, observability, guardrails, per-agent env, aggregate stats, 8 runtimes (incl. local Ollama/llama.cpp), shell completions, swarm patterns (fan-out/pipeline/debate/map-reduce), TUI dashboard, persistent sessions with `--recover`, token/cost tracking, file watcher, and ACP Registry discovery.

**What's next — adoption, not features.** sage is feature-complete for a 1.x orchestrator. The remaining work is getting people to know it exists.

| Track | Status |
|-------|--------|
| [awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents) listing | ✅ merged (PR #47, 2026-04-18) |
| Demo GIF in README | ✅ shipped (`docs/demo.sh` + `docs/demo.gif`) |
| `sage acp ls/show/install` — discover agents from ACP Registry | ✅ shipped |
| r/LocalLLaMA post (Ollama + sage CPU benchmark) | ✅ posted [1stvezm](https://www.reddit.com/r/LocalLLaMA/comments/1stvezm/) (2026-04-23) |
| HN Show launch post | 🚧 planned |
| Tembo "AI Coding Agents Compared" submission | 🚧 planned |
| Surgical refactor of top-4 giant functions | 🚧 planned (see [docs/REFACTOR-NOTES.md](docs/REFACTOR-NOTES.md)) |

See [ROADMAP.md](ROADMAP.md) for competitive analysis, weekly intel, and detailed specs.

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">
  <strong>⚡ sage</strong> — Because the best agent framework is the one you can read in an afternoon.
</p>
