# ⚡ sage — Simple Agent Engine

Unix-native agent dispatching and management. No frameworks, no npm packages — just bash, jq, and tmux.

## Install

```bash
git clone https://github.com/YouwangDeng/SageCLI.git
ln -s $(pwd)/sage/sage ~/bin/sage
sage init
```

## Quick Start

```bash
sage create worker --runtime claude-code   # or: cline, bash
sage start worker
sage call worker "Build hello.py that prints hello" 60
sage status
sage logs worker
```

Messages can be inline or read from a file:

```bash
sage send worker "Build hello.py"           # inline text
sage send worker @prompt.md                 # from file
sage call worker @detailed-task.txt 120     # file + sync wait
```

## Long-Running Tasks

Every task gets a trackable ID. Status transitions mechanically: `queued → running → done`.

```bash
# Submit (non-blocking, returns task ID)
sage send worker "Build the entire app"
# ✓ task t-1710347041 → worker

# Monitor
sage tasks worker                   # status + elapsed time
sage peek worker                    # live tmux pane + workspace
sage result t-1710347041            # structured result when done

# Course-correct
sage steer worker "Use REST, not GraphQL"              # soft: queued for next msg
sage steer worker "Wrong approach" --restart            # hard: cascade stop + retry
```

## Orchestration

Agents can create and manage other agents. Parent-child relationships are tracked automatically.

```bash
sage create orch --runtime claude-code
sage start orch
sage send orch "Build a todo app. Delegate to sub-agents."

# orch creates sub-agents (parent auto-tracked)
# sage status shows the tree:
#   orch           claude-code  running
#     └─ sub1      claude-code  running
#     └─ sub2      claude-code  running
```

## Multi-Orchestrator

Run multiple independent orchestrators in parallel:

```bash
sage create orch-frontend --runtime claude-code
sage create orch-backend --runtime claude-code
sage start --all

sage send orch-frontend "Build React dashboard"
sage send orch-backend "Build REST API with FastAPI"

sage tasks    # all tasks across all agents
sage status   # full tree view
```

## Steering

Course-correct agents without starting over:

```bash
# Soft steer — writes to steer.md, queued for next invocation
sage steer orch "Use PostgreSQL instead of SQLite"

# Hard steer — stops agent + all children, re-queues task with correction
sage steer orch "Wrong approach entirely" --restart
```

`--restart` cascades: stops all child agents, stops the orchestrator, writes the steering context, re-queues the in-flight task, and restarts. The orch re-creates sub-agents as needed.

## Runtimes

| Runtime | Backend | How it works |
|---|---|---|
| `bash` | Shell script | handler.sh processes messages |
| `cline` | Cline CLI | Each message invokes `cline --act` |
| `claude-code` | Claude Code CLI | Each message invokes `claude -p` (supports Bedrock) |

Adding a new runtime = one file with two functions. See [DEVELOPMENT.md](DEVELOPMENT.md).

## Architecture

- **Agents** = processes in tmux windows
- **Messages** = JSON files in inbox directories
- **Tasks** = tracked with IDs, status files, and result files
- **Parent-child** = auto-tracked via `SAGE_AGENT_NAME` env var
- **Sync calls** = reply files + polling
- **State** = files in workspace/
- **Steering** = steer.md injected into runtime prompts
- **Dependencies** = bash, jq, tmux

## Commands

```
AGENTS
  init [--force]                   Initialize ~/.sage/
  create <name> [--runtime R]      Create agent (bash|cline|claude-code)
  start [name|--all]               Start in tmux
  stop [name|--all]                Stop
  restart [name|--all]             Restart
  status                           Show all agents (tree view)
  ls                               List agent names
  rm <name>                        Remove agent
  clean                            Clean stale files

MESSAGING & TASKS
  send <to> <message|@file>     Fire-and-forget (returns task ID)
  call <to> <message|@file> [t]  Sync request/response (default: 60s)
  tasks [name]                     List tasks with status
  result <task-id>                 Get task result
  wait <name> [--timeout N]        Wait for agent to finish
  peek <name> [--lines N]          See tmux pane + workspace
  steer <name> <msg> [--restart]   Course-correct a running agent
  inbox [--json] [--clear]         View/clear messages

DEBUG
  logs <name> [-f|--clear]         View/tail/clear logs
  attach [name]                    Attach to tmux session

TOOLS
  tool add <name> <path>           Register a tool
  tool ls                          List tools
```
