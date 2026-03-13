# ⚡ sage — Simple Agent Engine

Unix-native agent dispatching and management. No frameworks, no npm packages — just bash, jq, and tmux.

## Install

```bash
# Clone and symlink
git clone git@github.com:YouwangDeng/sage.git
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
sage attach
```

## Orchestration

```bash
sage create orch --runtime claude-code
sage start orch
sage call orch '{"task":"Build X. Delegate to sub-agents."}' 300
# orch creates sub-agents, delegates, collects results, cleans up
```

## Runtimes

| Runtime | Backend | How it works |
|---|---|---|
| `bash` | Shell script | handler.sh processes messages |
| `cline` | Cline CLI | Each message invokes `cline --act` |
| `claude-code` | Claude Code CLI | Each message invokes `claude -p` (supports Bedrock) |

## Architecture

- **Agents** = processes in tmux
- **Messages** = JSON files in inbox directories
- **Sync calls** = reply files + polling
- **State** = files in workspace/
- **Dependencies** = bash, jq, tmux

## Commands

```
sage init [--force]              Initialize ~/.sage/
sage create <name> [--runtime R] Create agent
sage start [name|--all]          Start in tmux
sage stop [name|--all]           Stop
sage restart [name|--all]        Restart
sage status                      Show all agents
sage send <to> <json>            Fire-and-forget
sage call <to> <json> [timeout]  Sync request/response
sage logs <name> [-f|--clear]    View logs
sage attach [name]               Attach to tmux
sage rm <name>                   Remove agent
sage clean                       Clean stale files
```
