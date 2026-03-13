# sage Development Guide

## Architecture

```
sage (CLI)
  │
  ├── sage init          → creates ~/.sage/ with tools/, runtimes/, runner.sh
  ├── sage create <name> → creates agent dir with inbox/, workspace/, runtime.json
  ├── sage start <name>  → launches runner.sh in tmux pane
  ├── sage send/call     → writes JSON to agent's inbox/
  │
  └── runner.sh (per agent, runs in tmux)
        ├── polls inbox/ every 300ms
        ├── sources runtimes/<runtime>.sh
        └── calls runtime_inject() for each message
```

### File Layout

```
~/.sage/
├── agents/
│   ├── .cli/                  # pseudo-agent for sage call replies
│   │   └── replies/
│   └── <agent>/
│       ├── inbox/             # incoming messages (JSON files)
│       ├── replies/           # sync call responses
│       ├── workspace/         # agent's working directory
│       ├── state/             # persistent agent state
│       ├── runtime.json       # {"runtime":"cline","model":"","workdir":"..."}
│       ├── instructions.md    # auto-generated prompt for CLI runtimes
│       ├── handler.sh         # bash runtime only
│       └── .pid               # runner process ID
├── runtimes/
│   ├── bash.sh
│   ├── cline.sh
│   └── claude-code.sh
├── tools/
│   ├── common.sh              # send_msg, call_agent, reply, broadcast
│   └── llm.sh                 # raw LLM API helper
├── logs/
│   └── <agent>.log
└── runner.sh                  # agent process loop
```

## Message Flow

### Fire & Forget (sage send)
```
sage send worker '{"task":"do X"}'
  → writes JSON to ~/.sage/agents/worker/inbox/<msg_id>.json
  → runner picks it up, calls runtime_inject()
  → agent does work
  → agent runs: sage send <from> '{"result":"done"}'
```

### Sync Call (sage call)
```
sage call worker '{"task":"do X"}' 60
  → writes JSON with reply_dir to worker's inbox
  → polls reply_dir for response (up to 60s)
  → runner picks up message, calls runtime_inject()
  → runtime does work, captures output
  → runtime writes reply to reply_dir/<msg_id>.json
  → sage call reads reply, prints to stdout
```

### Key Design: Sync vs Async Prompt

When `reply_dir` is present (sync call via `sage call`):
- Prompt says: "Your output will be automatically returned. Do NOT run sage send."
- Result flows through reply_dir mechanism only

When `reply_dir` is absent (async via `sage send`):
- Prompt says: "Report result via sage send <from> ..."
- Agent must explicitly send results back

This prevents duplicate messages and wasted LLM invocations.

### Caller Identity

`sage call` uses `$SAGE_AGENT_NAME` if set (inside an agent), falls back to `.cli` from terminal.
This ensures sub-agents see `from=orch` (not `from=.cli`) when the orchestrator delegates.

## Runtime Interface

Every runtime implements exactly **two functions**:

```bash
runtime_start() {
  local agent_dir="$1" name="$2"
  # One-time setup when agent starts
}

runtime_inject() {
  local name="$1" msg="$2"
  # Called for each incoming message
  # Parse msg, build prompt, invoke CLI, write reply
}
```

## Adding a New Runtime

### Step 1: Create the bridge file

Create `runtimes/<name>.sh`:

```bash
#!/bin/bash
# Runtime: <name> bridge

runtime_start() {
  local agent_dir="$1" name="$2"
  mkdir -p "$agent_dir/workspace"
}

runtime_inject() {
  local name="$1" msg="$2"
  local agent_dir="$AGENTS_DIR/$name"

  # ── Parse message (copy this block as-is) ──
  local task=$(echo "$msg" | jq -r '.payload.task // .payload.text // (.payload | tostring)')
  local from=$(echo "$msg" | jq -r '.from')
  local msg_id=$(echo "$msg" | jq -r '.id')
  local reply_dir=$(echo "$msg" | jq -r '.reply_dir // empty')
  local workdir=$(jq -r '.workdir // "."' "$agent_dir/runtime.json")
  local model=$(jq -r '.model // empty' "$agent_dir/runtime.json")
  local instructions="$agent_dir/instructions.md"

  # ── Build prompt (copy this block as-is) ──
  local completion_instruction
  if [[ -n "$reply_dir" ]]; then
    completion_instruction="Your output will be automatically returned. Do NOT run sage send."
  else
    completion_instruction="When done: sage send $from '{\"status\":\"done\",\"agent\":\"$name\",\"result\":\"...\"}'"
  fi

  local prompt_file=$(mktemp /tmp/sage-XXXXX.txt)
  cat > "$prompt_file" << PROMPT
$(cat "$instructions" 2>/dev/null)

---
## Current Task (from: $from)
$task
---
$completion_instruction
PROMPT

  # ── Invoke the CLI (THIS IS THE ONLY PART YOU CUSTOMIZE) ──
  log "invoking <name>..."
  cd "$workdir"

  local output
  output=$(<YOUR_CLI_COMMAND> "$(cat "$prompt_file")" 2>&1) || true
  rm -f "$prompt_file"

  log "<name> finished (${#output} bytes)"

  # ── Write reply (copy this block as-is) ──
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    local json_output
    json_output=$(echo "$output" | jq -Rs .) || json_output="\"encoding failed\""
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_output}" > "$reply_dir/${msg_id}.json"
  fi
}
```

### Step 2: The CLI invocation (the only unique line)

```bash
# Cline
output=$(cline --act -c "$workdir" "$(cat "$prompt_file")" 2>&1) || true

# Claude Code (Bedrock)
export CLAUDE_CODE_USE_BEDROCK=1
output=$(cat "$prompt_file" | claude -p --output-format text --allowedTools "Bash(*)" "Write(*)" "Read(*)" "Edit(*)" 2>&1) || true

# Aider
output=$(aider --yes --message "$(cat "$prompt_file")" 2>&1) || true

# Gemini CLI
output=$(gemini -p "$(cat "$prompt_file")" 2>&1) || true

# Codex CLI
output=$(codex -q "$(cat "$prompt_file")" 2>&1) || true

# Ollama (local)
output=$(ollama run llama3 "$(cat "$prompt_file")" 2>&1) || true

# Any CLI that takes a prompt and writes to stdout
output=$(my-tool --prompt "$(cat "$prompt_file")" 2>&1) || true
```

### Step 3: Embed in sage init

Add the runtime to the `cmd_init()` function in `sage` so `sage init` deploys it:

```bash
  # ── Runtime: <name> ──
  cat > "$RUNTIMES_DIR/<name>.sh" << 'RTEOF'
  <paste your runtime here>
  RTEOF
```

### Step 4: Update help text

In `cmd_help()`, add the runtime to the RUNTIMES section.

### Step 5: Test

```bash
sage init --force
sage create test-agent --runtime <name>
sage start test-agent

# Simple task
sage call test-agent '{"task":"Create hello.py that prints hello"}' 60

# Verify
cat ~/.sage/agents/test-agent/workspace/hello.py
sage logs test-agent

# Clean up
sage stop test-agent
sage rm test-agent
```

### Checklist

- [ ] `runtimes/<name>.sh` created with `runtime_start` + `runtime_inject`
- [ ] CLI invocation works (test manually first: `<cli> "hello world"`)
- [ ] Prompt passed correctly (CLI arg vs stdin — check your CLI's docs)
- [ ] Output captured to `$output` variable
- [ ] Reply written for sync calls (`reply_dir` check)
- [ ] Embedded in `sage init` `cmd_init()`
- [ ] Help text updated
- [ ] End-to-end test: `sage call` returns result
- [ ] Orchestrator test: orch creates sub-agents with this runtime

## Dependencies

### Required
- `bash` (4.0+)
- `jq` (1.6+)
- `tmux` (3.0+)

### Optional (per runtime)
- `cline` — Cline CLI (`npm i -g @anthropic-ai/cline` or standalone)
- `claude` — Claude Code CLI (`npm i -g @anthropic-ai/claude-code`)
- Future: `aider`, `gemini`, `codex`, `ollama`

## Known Patterns

### Orchestrator Pattern
An agent that creates sub-agents, delegates, and collects results:
```
orch → sage create sub1 --runtime cline → sage call sub1 '{"task":"..."}' 120
     → sage create sub2 --runtime cline → sage call sub2 '{"task":"..."}' 120
     → copy results to workspace → verify → sage stop/rm sub-agents
```

### Persistent Agent
Agents stay alive between messages. The runner loops forever, processing each inbox message. Useful for multi-turn conversations (orch sends task, agent asks question, orch answers, agent continues).

### Mixed Runtimes
Orch can use claude-code while sub-agents use cline, or vice versa:
```bash
sage create orch --runtime claude-code
sage create fast-worker --runtime cline
sage create smart-worker --runtime claude-code
```
