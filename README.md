<p align="center">
  <img src="https://img.shields.io/badge/bash-4.0+-4EAA25?logo=gnubash&logoColor=white" alt="Bash 4.0+">
  <img src="https://img.shields.io/badge/jq-1.6+-CB171E?logo=jq&logoColor=white" alt="jq 1.6+">
  <img src="https://img.shields.io/badge/tmux-3.0+-1BB91F?logo=tmux&logoColor=white" alt="tmux 3.0+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <br>
  <img src="https://img.shields.io/badge/Claude_Code-supported-7C3AED?logo=anthropic&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/Cline-supported-F97316?logo=data:image/svg%2bxml;base64,PHN2ZyBmaWxsPSJ3aGl0ZSIgcm9sZT0iaW1nIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0ibTIzLjM2NSAxMy41NTYtMS40NDItMi44OTVWOC45OTRjMC0yLjc2NC0yLjIxOC01LjAwMi00Ljk1NC01LjAwMmgtMi40NjRjLjE3OC0uMzY3LjI3Ni0uNzc5LjI3Ni0xLjIxM0EyLjc3IDIuNzcgMCAwIDAgMTIuMDE4IDBhMi43NyAyLjc3IDAgMCAwLTIuNzYzIDIuNzc5YzAgLjQzNC4wOTguODQ2LjI3NiAxLjIxM0g3LjA2N2MtMi43MzYgMC00Ljk1NCAyLjIzOC00Ljk1NCA1LjAwMnYxLjY2N0wuNjQgMTMuNTQ5Yy0uMTQ5LjI5LS4xNDkuNjM2IDAgLjkyN2wxLjQ3MiAyLjg1NXYxLjY2N0MyLjExMyAyMS43NjIgNC4zMyAyNCA3LjA2NyAyNGg5LjkwMmMyLjczNiAwIDQuOTU0LTIuMjM4IDQuOTU0LTUuMDAyVjE3LjMzbDEuNDQtMi44NjVjLjE0My0uMjg2LjE0My0uNjIyLjAwMi0uOTFtLTEyLjg1NCAyLjM2YTIuMjcgMi4yNyAwIDAgMS0yLjI2MSAyLjI3MyAyLjI3IDIuMjcgMCAwIDEtMi4yNjEtMi4yNzN2LTQuMDQyQTIuMjcgMi4yNyAwIDAgMSA4LjI0OSA5LjZhMi4yNjcgMi4yNjcgMCAwIDEgMi4yNjIgMi4yNzR6bTcuMjg1IDBhMi4yNyAyLjI3IDAgMCAxLTIuMjYgMi4yNzMgMi4yNyAyLjI3IDAgMCAxLTIuMjYyLTIuMjczdi00LjA0MkEyLjI2NyAyLjI2NyAwIDAgMSAxNS41MzUgOS42YTIuMjY3IDIuMjY3IDAgMCAxIDIuMjYxIDIuMjc0eiIvPjwvc3ZnPg==" alt="Cline">
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

---

## Why sage?

Every AI coding agent framework wants you to learn a new language, install a runtime, and buy into an ecosystem. sage takes a different approach:

**Agents are processes. Messages are files. The terminal is your IDE.**

```bash
sage create worker --runtime claude-code
sage send worker "Build a REST API with auth, tests, and docs"
sage peek worker   # watch it work in real-time
```

That's it. Three commands. Your agent is running in a tmux pane, writing files, calling tools, and you can watch every step.

### Design Principles

- **Unix-native** — Agents are tmux windows. Messages are JSON files in directories. No daemons, no databases, no Docker.
- **Runtime-agnostic** — Plug in Claude Code, Cline, or any CLI. Adding a new runtime is one file with two functions.
- **Mechanical, not behavioral** — Task tracking, parent-child relationships, and tracing are handled by the engine, not by asking LLMs to remember protocols.
- **Observable** — Real-time streaming, `peek` into any agent, `trace` the full call tree. You always know what's happening.
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

**Optional runtimes:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), [Cline CLI](https://github.com/cline/cline)

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

### 🔨 Single Agent — Code Generation

Point an agent at a task and let it build:

```bash
sage create dev --runtime claude-code
sage send dev "Create a Node.js Express API with JWT auth, rate limiting, and Swagger docs"
sage peek dev    # watch files appear in real-time
```

### 🏗️ Multi-Agent Orchestration

One agent delegates to specialists:

```bash
sage create orch --runtime claude-code
sage send orch "Build a full-stack todo app. Create sub-agents for frontend and backend."

sage status
#  orch              claude-code  running   45s
#    └─ frontend     claude-code  running   30s
#    └─ backend      claude-code  running   28s

sage trace --tree
#  t-001 cli → orch "Build a full-stack todo app" (120s) ✓
#    ├─ t-002 orch → frontend "Build React UI with..." (45s) ✓
#    └─ t-003 orch → backend "Build Express API with..." (52s) ✓
```

### ⚡ Parallel Workstreams

Run independent orchestrators simultaneously:

```bash
sage create orch-api --runtime claude-code
sage create orch-ui --runtime claude-code
sage create orch-infra --runtime claude-code

sage send orch-api "Build REST API with FastAPI"
sage send orch-ui "Build React dashboard"
sage send orch-infra "Write Terraform for AWS ECS"

sage tasks    # track everything
sage status   # full tree view
```

### 🎯 Course Correction

Steer agents without losing progress:

```bash
# Soft steer — guidance for the next task
sage steer orch "Use PostgreSQL instead of SQLite"

# Hard steer — stop everything, restart with new direction
sage steer orch "Switch to Go instead of Python" --restart
# Cascades: stops all children → restarts orch with context
```

### 🔄 Mixed Runtimes

Use the right tool for each job:

```bash
sage create planner --runtime claude-code    # strong reasoning
sage create coder --runtime cline            # fast execution
sage create scripts --runtime bash           # custom handlers
```

### 📋 Sync Calls

When you need the answer right now:

```bash
# Blocks until done (60s default timeout)
sage call worker "What's the time complexity of merge sort?" 30

# Perfect for scripting
RESULT=$(sage call analyzer "Review this PR" 120)
echo "$RESULT"
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
| `cline` | [Cline CLI](https://github.com/cline/cline) | ✅ json | Real-time events via `--json` |
| `bash` | Shell script | — | Custom `handler.sh` processes messages |

Adding a runtime is one file with two functions (`runtime_start` + `runtime_inject`). See [DEVELOPMENT.md](DEVELOPMENT.md).

---

## Architecture

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
├── runtimes/           # bash, cline, claude-code
├── tools/              # shared utilities
├── trace.jsonl         # append-only event log
└── runner.sh           # agent process loop
```

---

## Commands

```
AGENTS
  init [--force]                     Initialize ~/.sage/
  create <name> [--runtime R]        Create agent (bash|cline|claude-code)
  start [name|--all]                 Start in tmux
  stop [name|--all]                  Stop (kills process group)
  restart [name|--all]               Restart
  status                             Tree view of all agents
  ls                                 List agent names
  rm <name>                          Remove agent
  clean                              Clean stale files

MESSAGING & TASKS
  send <to> <message|@file>          Fire-and-forget (returns task ID)
  call <to> <message|@file> [t]      Sync request/response (default 60s)
  tasks [name]                       List tasks with status
  result <task-id>                   Get task result
  wait <name> [--timeout N]          Wait for agent to finish
  peek <name> [--lines N]            Live output + workspace
  steer <name> <msg> [--restart]     Course-correct agent
  inbox [--json] [--clear]           View/clear CLI messages

DEBUG & OBSERVABILITY
  logs <name> [-f|--clear]           View/tail/clear logs
  trace [name] [--tree] [-n N]       Agent interaction trace
  attach [name]                      Attach to tmux session

TOOLS
  tool add <name> <path>             Register a tool
  tool ls                            List tools
```

---

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
# The entire engine
wc -l sage    # ~1500 lines

# Run from source
./sage init --force
./sage create test --runtime bash
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture details, runtime interface, and how to add new runtimes.

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">
  <strong>⚡ sage</strong> — Because the best agent framework is the one you can read in an afternoon.
</p>
