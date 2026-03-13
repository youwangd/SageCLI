# ⚡ sage — Simple Agent Engine

Unix-native agent dispatching and management. No frameworks, no npm packages — just bash, jq, and tmux.

## Install

```bash
git clone https://github.com/YouwangDeng/sage.git
ln -s $(pwd)/sage/sage ~/bin/sage
sage init
```

## Quick Start

```bash
sage create worker --runtime claude-code   # or: cline, bash
sage start worker
sage call worker '{"task":"Build hello.py"}' 60
sage status
sage logs worker
```

## Orchestration

Agents can create and manage other agents:

```bash
sage create orch --runtime claude-code
sage start orch
sage call orch '{"task":"Build X. Delegate to sub-agents."}' 300
# orch creates sub-agents, delegates, collects results, cleans up
```

## Long-Running Tasks

```bash
sage send orch '{"task":"Build the entire app..."}'   # non-blocking
sage wait orch --timeout 3600                          # stream progress, notify on completion
sage inbox                                             # check results
sage logs orch -f                                      # live tail
```

## Runtimes

| Runtime | Backend | How it works |
|---|---|---|
| `bash` | Shell script | handler.sh processes messages |
| `cline` | Cline CLI | Each message invokes `cline --act` |
| `claude-code` | Claude Code CLI | Each message invokes `claude -p` (supports Bedrock) |

Adding a new runtime = one file with two functions. See [DEVELOPMENT.md](DEVELOPMENT.md).

## Architecture

- **Agents** = processes in tmux
- **Messages** = JSON files in inbox directories
- **Sync calls** = reply files + polling
- **State** = files in workspace/
- **Dependencies** = bash, jq, tmux

## Commands

```
AGENTS
  init [--force]              Initialize ~/.sage/
  create <name> [--runtime R] Create agent (bash|cline|claude-code)
  start [name|--all]          Start in tmux
  stop [name|--all]           Stop
  restart [name|--all]        Restart
  status                      Show all agents
  ls                          List agent names
  rm <name>                   Remove agent
  clean                       Clean stale files

MESSAGING
  send <to> <json>            Fire-and-forget
  call <to> <json> [timeout]  Sync request/response (default: 60s)
  wait <name> [--timeout N]   Wait for agent to finish (long-running)
  inbox [--json] [--clear]    View/clear messages sent to you

DEBUG
  logs <name> [-f|--clear]    View/tail/clear logs
  attach [name]               Attach to tmux session

TOOLS
  tool add <name> <path>      Register a tool
  tool ls                     List tools
```
