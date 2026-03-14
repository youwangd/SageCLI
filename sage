#!/bin/bash
# sage — Simple Agent Engine
# Unix-native agent dispatching and management
# Dependencies: bash, jq, tmux

set -euo pipefail

SAGE_HOME="${SAGE_HOME:-$HOME/.sage}"
AGENTS_DIR="$SAGE_HOME/agents"
TOOLS_DIR="$SAGE_HOME/tools"
RUNTIMES_DIR="$SAGE_HOME/runtimes"
LOGS_DIR="$SAGE_HOME/logs"
TMUX_SESSION="sage"

# ═══ Colors ═══
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; DIM='\033[2m'
BOLD='\033[1m'; NC='\033[0m'

die()  { echo -e "${RED}error:${NC} $*" >&2; exit 1; }
info() { echo -e "${CYAN}▸${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

ensure_init() { [[ -d "$SAGE_HOME" ]] || die "not initialized. Run: sage init"; }
agent_exists() { [[ -d "$AGENTS_DIR/$1" ]] || die "agent '$1' not found"; }

agent_pid() {
  local pidfile="$AGENTS_DIR/$1/.pid"
  if [[ -f "$pidfile" ]]; then
    local pid=$(cat "$pidfile")
    kill -0 "$pid" 2>/dev/null && echo "$pid" && return 0
  fi
  return 1
}

# Find all children of an agent (recursive)
agent_children() {
  local parent="$1"
  for d in "$AGENTS_DIR"/*/runtime.json; do
    [[ -f "$d" ]] || continue
    local child_name=$(basename "$(dirname "$d")")
    local child_parent=$(jq -r '.parent // ""' "$d" 2>/dev/null)
    if [[ "$child_parent" == "$parent" ]]; then
      echo "$child_name"
      # Recurse for grandchildren
      agent_children "$child_name"
    fi
  done
}

# ═══════════════════════════════════════════════
# sage init [--force]
# ═══════════════════════════════════════════════
cmd_init() {
  local force=false
  [[ "${1:-}" == "--force" ]] && force=true

  if [[ -d "$SAGE_HOME" && "$force" != true ]]; then
    warn "already initialized at $SAGE_HOME (use --force to reinitialize)"
    return
  fi

  mkdir -p "$AGENTS_DIR" "$TOOLS_DIR" "$RUNTIMES_DIR" "$LOGS_DIR" "$AGENTS_DIR/.cli/replies"

  # ── common.sh ──
  cat > "$TOOLS_DIR/common.sh" << 'TOOLEOF'
#!/bin/bash
SAGE_HOME="${SAGE_HOME:-$HOME/.sage}"
AGENTS_DIR="$SAGE_HOME/agents"

# Generate a short task ID
_task_id() {
  echo "t-$(date +%s)-$RANDOM"
}

# Append to shared trace log
_trace() {
  local event="$1"
  echo "$event" >> "$SAGE_HOME/trace.jsonl" 2>/dev/null
}

send_msg() {
  local to="$1" payload="$2"
  local task_id="$(_task_id)"
  local me="${SAGE_AGENT_NAME:-cli}"
  local inbox="$AGENTS_DIR/$to/inbox"
  # .cli is a special pseudo-agent — accept it as a target
  if [[ "$to" == ".cli" ]]; then
    mkdir -p "$AGENTS_DIR/.cli/inbox"
    inbox="$AGENTS_DIR/.cli/inbox"
  fi
  [[ -d "$inbox" ]] || { echo "error: agent '$to' not found" >&2; return 1; }

  # Create task tracking
  local results_dir="$AGENTS_DIR/$to/results"
  mkdir -p "$results_dir"
  jq -n \
    --arg id "$task_id" \
    --arg from "$me" \
    --arg status "queued" \
    --arg ts "$(date +%s)" \
    '{id:$id, from:$from, status:$status, queued_at:($ts|tonumber), started_at:null, finished_at:null}' \
    > "$results_dir/${task_id}.status.json"

  # Write message to inbox
  cat > "$inbox/${task_id}.json" <<MSGEOF
{"id":"$task_id","from":"$me","payload":$payload,"ts":$(date +%s)}
MSGEOF

  # Trace
  local text_preview=$(echo "$payload" | jq -r '.text // (.task // "")' 2>/dev/null | head -c 80)
  _trace "{\"ts\":$(date +%s),\"type\":\"send\",\"from\":\"$me\",\"to\":\"$to\",\"task_id\":\"$task_id\",\"text\":$(echo "$text_preview" | jq -Rs .)}"

  # Return task_id so callers can track it
  echo "$task_id"
}

call_agent() {
  local to="$1" payload="$2" timeout="${3:-60}"
  local task_id="$(_task_id)"
  local me="${SAGE_AGENT_NAME:-cli}"
  local reply_dir="$AGENTS_DIR/${me}/replies"
  mkdir -p "$reply_dir"
  local inbox="$AGENTS_DIR/$to/inbox"
  [[ -d "$inbox" ]] || { echo "error: agent '$to' not found" >&2; return 1; }

  # Create task tracking
  local results_dir="$AGENTS_DIR/$to/results"
  mkdir -p "$results_dir"
  jq -n \
    --arg id "$task_id" \
    --arg from "$me" \
    --arg status "queued" \
    --arg ts "$(date +%s)" \
    '{id:$id, from:$from, status:$status, queued_at:($ts|tonumber), started_at:null, finished_at:null}' \
    > "$results_dir/${task_id}.status.json"

  cat > "$inbox/${task_id}.json" <<MSGEOF
{"id":"$task_id","from":"$me","payload":$payload,"reply_dir":"$reply_dir","ts":$(date +%s)}
MSGEOF

  # Trace
  local text_preview=$(echo "$payload" | jq -r '.text // (.task // "")' 2>/dev/null | head -c 80)
  _trace "{\"ts\":$(date +%s),\"type\":\"send\",\"from\":\"$me\",\"to\":\"$to\",\"task_id\":\"$task_id\",\"text\":$(echo "$text_preview" | jq -Rs .)}"

  local deadline=$((SECONDS + timeout))
  while [[ $SECONDS -lt $deadline ]]; do
    if [[ -f "$reply_dir/${task_id}.json" ]]; then
      cat "$reply_dir/${task_id}.json"
      rm "$reply_dir/${task_id}.json"
      return 0
    fi
    sleep 0.3
  done
  echo "error: timeout waiting for reply from '$to' (task: $task_id — still running, use: sage result $task_id)" >&2
  return 1
}

reply() {
  local msg="$1" result="$2"
  local reply_dir=$(echo "$msg" | jq -r '.reply_dir // empty')
  local msg_id=$(echo "$msg" | jq -r '.id')
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    echo "$result" > "$reply_dir/${msg_id}.json"
  fi
}

broadcast() {
  local payload="$1"
  for d in "$AGENTS_DIR"/*/; do
    local n=$(basename "$d")
    [[ "$n" == "${SAGE_AGENT_NAME:-}" || "$n" == .* ]] && continue
    send_msg "$n" "$payload" 2>/dev/null || true
  done
}
TOOLEOF

  # ── llm.sh ──
  cat > "$TOOLS_DIR/llm.sh" << 'TOOLEOF'
#!/bin/bash
llm() {
  local prompt="$1" model="${2:-claude-sonnet-4-20250514}"
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    curl -s https://api.anthropic.com/v1/messages \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$(jq -n --arg m "$model" --arg p "$prompt" \
        '{model:$m,max_tokens:4096,messages:[{role:"user",content:$p}]}')" \
      | jq -r '.content[0].text'
  elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    curl -s https://api.openai.com/v1/chat/completions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -H "content-type: application/json" \
      -d "$(jq -n --arg m "${model:-gpt-4o}" --arg p "$prompt" \
        '{model:$m,messages:[{role:"user",content:$p}]}')" \
      | jq -r '.choices[0].message.content'
  else
    echo "error: no LLM API key set" >&2; return 1
  fi
}
TOOLEOF

  # ── Runtime: bash ──
  cat > "$RUNTIMES_DIR/bash.sh" << 'RTEOF'
#!/bin/bash
# Runtime: bash handler

runtime_start() {
  local agent_dir="$1" name="$2"
  for tool in "$SAGE_HOME/tools"/*.sh; do
    [[ -f "$tool" ]] && source "$tool"
  done
  source "$agent_dir/handler.sh"
}

runtime_inject() {
  local name="$1" msg="$2"
  handle_message "$msg"
}
RTEOF

  # ── Runtime: cline ──
  cat > "$RUNTIMES_DIR/cline.sh" << 'RTEOF'
#!/bin/bash
# Runtime: cline CLI bridge
# Each message invokes cline --act directly in the runner process

runtime_start() {
  local agent_dir="$1" name="$2"
  mkdir -p "$agent_dir/workspace"
}

runtime_inject() {
  local name="$1" msg="$2"
  local agent_dir="$AGENTS_DIR/$name"
  local task=$(echo "$msg" | jq -r '.payload.text // (.payload | tostring)' 2>/dev/null)
  local from=$(echo "$msg" | jq -r '.from' 2>/dev/null)
  local msg_id=$(echo "$msg" | jq -r '.id' 2>/dev/null)
  local reply_dir=$(echo "$msg" | jq -r '.reply_dir // empty' 2>/dev/null)
  local workdir=$(jq -r '.workdir // "."' "$agent_dir/runtime.json" 2>/dev/null)
  local model=$(jq -r '.model // empty' "$agent_dir/runtime.json" 2>/dev/null)
  local instructions="$agent_dir/instructions.md"

  # Build completion instruction based on call type
  local completion_instruction
  if [[ -n "$reply_dir" ]]; then
    completion_instruction="Your output will be automatically returned to the caller. Do NOT run sage send — just do the work and let your output speak for itself."
  else
    completion_instruction="When you complete this task, report your result by running:
sage send $from \"Done: <brief summary of what you did>\""
  fi

  # Write prompt to temp file
  local prompt_file=$(mktemp /tmp/sage-cline-XXXXX.txt)
  local steer_file="$agent_dir/steer.md"
  cat > "$prompt_file" << PROMPT
$(cat "$instructions" 2>/dev/null)
$(if [[ -f "$steer_file" ]]; then echo ""; cat "$steer_file"; fi)

---
## Current Task (from: $from)
$task
---
$completion_instruction
PROMPT

  log "invoking cline..."
  local output
  cd "$workdir"

  local cline_args=(--act -c "$workdir")
  [[ -n "$model" ]] && cline_args+=(-m "$model")

  local live_output="$agent_dir/.live_output"
  > "$live_output"
  tail -f "$live_output" &
  local tail_pid=$!
  cline "${cline_args[@]}" "$(cat "$prompt_file")" > "$live_output" 2>&1 || true
  sleep 0.2; kill "$tail_pid" 2>/dev/null; wait "$tail_pid" 2>/dev/null
  output=$(cat "$live_output")
  rm -f "$prompt_file"

  log "cline finished: $(echo "$output" | tail -1 | head -c 120)"

  # Write result for task tracking
  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$results_dir/${msg_id}.result.json" 2>/dev/null
  fi

  # Write reply for sync calls
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$(echo "$output" | jq -Rs .)}" > "$reply_dir/${msg_id}.json"
  fi
}
RTEOF

  # ── Runtime: claude-code ──
  cat > "$RUNTIMES_DIR/claude-code.sh" << 'RTEOF'
#!/bin/bash
# Runtime: claude-code CLI bridge
# Each message invokes `claude -p` (print mode) in the runner process

runtime_start() {
  local agent_dir="$1" name="$2"
  mkdir -p "$agent_dir/workspace"
}

runtime_inject() {
  local name="$1" msg="$2"
  local agent_dir="$AGENTS_DIR/$name"
  local task=$(echo "$msg" | jq -r '.payload.text // (.payload | tostring)' 2>/dev/null)
  local from=$(echo "$msg" | jq -r '.from' 2>/dev/null)
  local msg_id=$(echo "$msg" | jq -r '.id' 2>/dev/null)
  local reply_dir=$(echo "$msg" | jq -r '.reply_dir // empty' 2>/dev/null)
  local workdir=$(jq -r '.workdir // "."' "$agent_dir/runtime.json" 2>/dev/null)
  local model=$(jq -r '.model // empty' "$agent_dir/runtime.json" 2>/dev/null)
  local instructions="$agent_dir/instructions.md"

  # Build completion instruction based on call type
  local completion_instruction
  if [[ -n "$reply_dir" ]]; then
    completion_instruction="Your output will be automatically returned to the caller. Do NOT run sage send — just do the work and let your output speak for itself."
  else
    completion_instruction="When you complete this task, report your result by running:
sage send $from \"Done: <brief summary of what you did>\""
  fi

  # Write prompt to temp file
  local prompt_file=$(mktemp /tmp/sage-claude-XXXXX.txt)
  local steer_file="$agent_dir/steer.md"
  cat > "$prompt_file" << PROMPT
$(cat "$instructions" 2>/dev/null)
$(if [[ -f "$steer_file" ]]; then echo ""; cat "$steer_file"; fi)

---
## Current Task (from: $from)
$task
---
$completion_instruction
PROMPT

  export CLAUDE_CODE_USE_BEDROCK=1

  log "invoking claude-code..."
  local output
  cd "$workdir"

  local claude_args=(-p --output-format text --allowedTools "Bash(*)" "Write(*)" "Read(*)" "Edit(*)")
  [[ -n "$model" ]] && claude_args+=(--model "$model")

  local live_output="$agent_dir/.live_output"
  > "$live_output"

  # Write claude command to a temp script to avoid quoting issues
  local cmd_script=$(mktemp /tmp/sage-run-XXXXX.sh)
  {
    echo '#!/bin/bash'
    echo "cd $(printf '%q' "$workdir")"
    printf 'cat %q | claude' "$prompt_file"
    for arg in "${claude_args[@]}"; do
      printf ' %q' "$arg"
    done
    echo ""
  } > "$cmd_script"
  chmod +x "$cmd_script"

  # Use script(1) with --flush to allocate a PTY and stream output in real-time
  script -qefc "$cmd_script" --flush "$live_output" || true

  # Clean script artifacts
  output=$(sed '/^Script started/d; /^Script done/d' "$live_output" | tr -d '\r')
  rm -f "$prompt_file" "$cmd_script"

  log "claude-code finished: $(echo "$output" | tail -1 | head -c 120)"

  # Write result for task tracking
  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$results_dir/${msg_id}.result.json" 2>/dev/null
  fi

  # Write reply for sync calls
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$(echo "$output" | jq -Rs .)}" > "$reply_dir/${msg_id}.json"
  fi
}
RTEOF

  # ── Runner ──
  cat > "$SAGE_HOME/runner.sh" << 'RUNNER'
#!/bin/bash
set -uo pipefail

AGENT_DIR="$1"
AGENT_NAME="$(basename "$AGENT_DIR")"
INBOX="$AGENT_DIR/inbox"
STATE="$AGENT_DIR/state"

export SAGE_AGENT_NAME="$AGENT_NAME"
export SAGE_HOME="${SAGE_HOME:-$HOME/.sage}"
AGENTS_DIR="$SAGE_HOME/agents"
LOGS="$SAGE_HOME/logs"

# Ensure PATH includes common tool locations
export PATH="$HOME/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"

mkdir -p "$INBOX" "$STATE" "$AGENT_DIR/replies"

# Read runtime config
RUNTIME=$(jq -r '.runtime // "bash"' "$AGENT_DIR/runtime.json" 2>/dev/null || echo "bash")

# Source tools
for tool in "$SAGE_HOME/tools"/*.sh; do
  [[ -f "$tool" ]] && source "$tool"
done

# Source runtime bridge
source "$SAGE_HOME/runtimes/${RUNTIME}.sh"

# Write PID
echo $$ > "$AGENT_DIR/.pid"

log() { echo "[$(date '+%H:%M:%S')] $AGENT_NAME: $*" | tee -a "$LOGS/$AGENT_NAME.log"; }

log "online (runtime=$RUNTIME)"

# For non-bash runtimes, initialize
if [[ "$RUNTIME" != "bash" ]]; then
  sleep 0.5
  log "starting $RUNTIME runtime"
  runtime_start "$AGENT_DIR" "$AGENT_NAME"
else
  runtime_start "$AGENT_DIR" "$AGENT_NAME"
fi

# Main loop: process inbox
while true; do
  for msg_file in "$INBOX"/*.json; do
    [[ -f "$msg_file" ]] || continue
    msg=$(cat "$msg_file")
    rm -f "$msg_file"
    local_task_id=$(echo "$msg" | jq -r '.id')
    local_from=$(echo "$msg" | jq -r '.from')
    log "← ${local_from}: $(echo "$msg" | jq -c '.payload' | head -c 100)"

    # Update task status → running
    results_dir="$AGENT_DIR/results"
    mkdir -p "$results_dir"
    status_file="$results_dir/${local_task_id}.status.json"
    if [[ -f "$status_file" ]]; then
      jq --arg ts "$(date +%s)" '.status="running" | .started_at=($ts|tonumber)' "$status_file" > "${status_file}.tmp" && mv "${status_file}.tmp" "$status_file"
    fi

    # Trace: task started
    echo "{\"ts\":$(date +%s),\"type\":\"start\",\"agent\":\"$AGENT_NAME\",\"task_id\":\"$local_task_id\",\"from\":\"$local_from\"}" >> "$SAGE_HOME/trace.jsonl" 2>/dev/null

    # Process the message
    task_start_ts=$(date +%s)
    runtime_inject "$AGENT_NAME" "$msg"
    task_elapsed=$(( $(date +%s) - task_start_ts ))

    # Update task status → done
    if [[ -f "$status_file" ]]; then
      jq --arg ts "$(date +%s)" '.status="done" | .finished_at=($ts|tonumber)' "$status_file" > "${status_file}.tmp" && mv "${status_file}.tmp" "$status_file"
    fi

    # Trace: task done
    echo "{\"ts\":$(date +%s),\"type\":\"done\",\"agent\":\"$AGENT_NAME\",\"task_id\":\"$local_task_id\",\"elapsed\":$task_elapsed}" >> "$SAGE_HOME/trace.jsonl" 2>/dev/null
  done
  sleep 0.3
done
RUNNER
  chmod +x "$SAGE_HOME/runner.sh"

  ok "sage initialized at $SAGE_HOME"
}

# ═══════════════════════════════════════════════
# sage create <name> [--runtime <rt>] [--model <m>]
# ═══════════════════════════════════════════════
cmd_create() {
  local name="" runtime="bash" model="" parent=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --runtime|-r) runtime="$2"; shift 2 ;;
      --model|-m)   model="$2"; shift 2 ;;
      --parent)     parent="$2"; shift 2 ;;
      -*)           die "unknown flag: $1" ;;
      *)            name="$1"; shift ;;
    esac
  done

  [[ -n "$name" ]] || die "usage: sage create <name> [--runtime bash|cline|claude-code] [--model <model>]"
  ensure_init

  # Auto-set parent from SAGE_AGENT_NAME if running inside an agent
  if [[ -z "$parent" && -n "${SAGE_AGENT_NAME:-}" && "${SAGE_AGENT_NAME}" != "cli" ]]; then
    parent="$SAGE_AGENT_NAME"
  fi

  local agent_dir="$AGENTS_DIR/$name"
  [[ ! -d "$agent_dir" ]] || die "agent '$name' already exists"

  # Validate runtime
  [[ -f "$RUNTIMES_DIR/${runtime}.sh" ]] || die "unknown runtime: $runtime (available: $(ls "$RUNTIMES_DIR" | sed 's/.sh//' | tr '\n' ' '))"

  mkdir -p "$agent_dir"/{inbox,state,replies,workspace}

  # Write runtime config
  jq -n \
    --arg rt "$runtime" \
    --arg m "$model" \
    --arg p "$parent" \
    --arg wd "$agent_dir/workspace" \
    '{runtime:$rt, model:$m, parent:$p, workdir:$wd, created:(now|todate)}' \
    > "$agent_dir/runtime.json"

  # Generate instructions for CLI runtimes
  if [[ "$runtime" != "bash" ]]; then
    cat > "$agent_dir/instructions.md" << INST
# You are sage agent: $name

You are a persistent agent in the sage system. You communicate with other agents using shell commands.

## Communication Commands

\`\`\`bash
# Send a message to another agent (fire & forget)
sage send <agent-name> "description of what to do"

# See who's running
sage status

# Create a sub-agent (if you need to delegate)
sage create <name> --runtime $runtime
sage start <name>
sage send <name> "do this task"

# Send and wait for a response (sync, 60s default timeout)
sage call <name> "do this task" 120

# Stop/remove agents you created
sage stop <name>
sage rm <name>
\`\`\`

## Your Identity
- Agent name: $name
- Runtime: $runtime
- Parent: ${parent:-none}
- Workspace: $agent_dir/workspace

## Rules
- You receive tasks as messages. Do the work.
- Use \`sage send\` to communicate results back to whoever sent you the task.
- If you need clarification, use \`sage send <from> "your question here"\`
- If you need to delegate subtasks, create sub-agents with \`sage create\`
- Keep your work in your workspace directory.
- When done with a task, always send the result back.
INST
  else
    cat > "$agent_dir/handler.sh" << 'HANDLER'
#!/bin/bash
handle_message() {
  local msg="$1"
  local from=$(echo "$msg" | jq -r '.from')
  local payload=$(echo "$msg" | jq -c '.payload')
  echo "received from $from: $payload"
  reply "$msg" "{\"echo\": $payload}"
}
HANDLER
    chmod +x "$agent_dir/handler.sh"
  fi

  ok "agent '$name' created (runtime=$runtime)"
  if [[ "$runtime" == "bash" ]]; then
    info "edit $agent_dir/handler.sh to add logic"
  else
    info "edit $agent_dir/instructions.md to customize behavior"
  fi
}

# ═══════════════════════════════════════════════
# sage start [name|--all]
# ═══════════════════════════════════════════════
cmd_start() {
  local target="${1:-}"
  ensure_init

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$TMUX_SESSION" -n "hub" "echo '⚡ sage hub — $(date)'; bash"
  fi

  if [[ "$target" == "--all" || -z "$target" ]]; then
    local started=0
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      start_agent "$n" && ((started++)) || true
    done
    [[ $started -gt 0 ]] && ok "started $started agent(s)" || warn "no agents found"
  else
    agent_exists "$target"
    start_agent "$target"
  fi
}

start_agent() {
  local name="$1"
  if agent_pid "$name" >/dev/null 2>&1; then
    warn "$name already running (pid $(agent_pid "$name"))"
    return 1
  fi

  local runtime=$(jq -r '.runtime // "bash"' "$AGENTS_DIR/$name/runtime.json" 2>/dev/null || echo "bash")

  tmux new-window -t "$TMUX_SESSION" -n "$name" \
    "bash $SAGE_HOME/runner.sh $AGENTS_DIR/$name; echo '[exited — press enter]'; read" 2>/dev/null

  ok "started $name (runtime=$runtime)"
}

# ═══════════════════════════════════════════════
# sage stop [name|--all]
# ═══════════════════════════════════════════════
cmd_stop() {
  local target="${1:-}"
  ensure_init

  if [[ "$target" == "--all" || -z "$target" ]]; then
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      stop_agent "$n"
    done
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null && info "tmux session closed"
  else
    agent_exists "$target"
    stop_agent "$target"
  fi
}

stop_agent() {
  local name="$1" pid
  if pid=$(agent_pid "$name"); then
    # Kill entire process group (catches child cline/claude processes)
    local pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -n "$pgid" ]]; then
      kill -- -"$pgid" 2>/dev/null || true
    fi
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
    rm -f "$AGENTS_DIR/$name/.pid"
    tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null
    ok "stopped $name (pid $pid)"
  else
    info "$name not running"
  fi
}

# ═══════════════════════════════════════════════
# sage restart [name|--all]
# ═══════════════════════════════════════════════
cmd_restart() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "usage: sage restart <name|--all>"
  ensure_init

  if [[ "$target" == "--all" ]]; then
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      stop_agent "$n" 2>/dev/null
      start_agent "$n"
    done
  else
    agent_exists "$target"
    stop_agent "$target" 2>/dev/null
    start_agent "$target"
  fi
}

# ═══════════════════════════════════════════════
# sage status
# ═══════════════════════════════════════════════
cmd_status() {
  set +e
  ensure_init

  printf "\n${BOLD}  ⚡ SAGE — Simple Agent Engine${NC}\n"
  printf "  ${DIM}%s${NC}\n\n" "$SAGE_HOME"

  local count=0
  printf "  ${DIM}%-16s %-12s %-10s %-8s %-6s %s${NC}\n" "AGENT" "RUNTIME" "STATUS" "PID" "INBOX" "LAST"

  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local name=$(basename "$agent_dir")
    [[ "$name" == .* ]] && continue

    local runtime=$(jq -r '.runtime // "bash"' "$agent_dir/runtime.json" 2>/dev/null || echo "bash")
    local inbox_count=$(find "$agent_dir/inbox" -name "*.json" 2>/dev/null | wc -l)
    local pid status_color status_text pid_text last_active

    if pid=$(agent_pid "$name"); then
      status_color="$GREEN"
      status_text="running"
      pid_text="$pid"
    else
      status_color="$DIM"
      status_text="stopped"
      pid_text="—"
    fi

    local logfile="$LOGS_DIR/$name.log"
    last_active=$(tail -1 "$logfile" 2>/dev/null | grep -oP '^\[\K[0-9:]+' || echo "—")

    local parent=$(jq -r '.parent // ""' "$agent_dir/runtime.json" 2>/dev/null)
    local display_name="$name"
    [[ -n "$parent" ]] && display_name="  └─ $name"

    printf "  %-16s %-12s ${status_color}%-10s${NC} %-8s %-6s %s\n" \
      "$display_name" "$runtime" "$status_text" "$pid_text" "$inbox_count" "$last_active"
    ((count++))
  done

  [[ $count -eq 0 ]] && printf "  ${DIM}no agents. Run: sage create <name>${NC}\n"

  printf "\n"
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    printf "  ${GREEN}●${NC} tmux: ${BOLD}$TMUX_SESSION${NC} (sage attach to view)\n"
  else
    printf "  ${DIM}○ tmux: not running${NC}\n"
  fi
  printf "\n"
}

# ═══════════════════════════════════════════════
# sage send <to> <payload>
# ═══════════════════════════════════════════════
cmd_send() {
  local to="${1:-}" message="${2:-}"
  [[ -n "$to" && -n "$message" ]] || die "usage: sage send <agent> <message|@file>"
  ensure_init

  if [[ "$to" != ".cli" ]]; then
    agent_exists "$to"
    # Auto-start if not running
    if ! agent_pid "$to" >/dev/null 2>&1; then
      cmd_start "$to"
    fi
  fi

  # Support @file syntax — read message from file
  if [[ "$message" == @* ]]; then
    local filepath="${message#@}"
    filepath="${filepath/#\~/$HOME}"
    [[ -f "$filepath" ]] || die "file not found: $filepath"
    message=$(cat "$filepath")
  fi

  export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
  source "$TOOLS_DIR/common.sh"

  local payload
  payload="$(jq -n --arg t "$message" '{text:$t}')"

  local task_id
  task_id=$(send_msg "$to" "$payload")
  ok "task ${BOLD}${task_id}${NC} → $to"
  info "track: sage tasks $to | sage result $task_id"
}

# ═══════════════════════════════════════════════
# sage call <to> <payload> [timeout]
# ═══════════════════════════════════════════════
cmd_call() {
  local to="${1:-}" message="${2:-}" timeout="${3:-60}"
  [[ -n "$to" && -n "$message" ]] || die "usage: sage call <agent> <message|@file> [timeout]"
  ensure_init; agent_exists "$to"

  # Auto-start if not running
  if ! agent_pid "$to" >/dev/null 2>&1; then
    cmd_start "$to"
  fi

  # Support @file syntax
  if [[ "$message" == @* ]]; then
    local filepath="${message#@}"
    filepath="${filepath/#\~/$HOME}"
    [[ -f "$filepath" ]] || die "file not found: $filepath"
    message=$(cat "$filepath")
  fi

  # Use the agent's own name if running inside an agent, otherwise .cli
  local caller="${SAGE_AGENT_NAME:-.cli}"
  mkdir -p "$AGENTS_DIR/$caller/replies"
  export SAGE_AGENT_NAME="$caller"
  source "$TOOLS_DIR/common.sh"

  local payload
  payload="$(jq -n --arg t "$message" '{text:$t}')"

  call_agent "$to" "$payload" "$timeout" || die "no response within ${timeout}s"
}

# ═══════════════════════════════════════════════
# sage logs <name> [-f] [--clear]
# ═══════════════════════════════════════════════
cmd_logs() {
  local name="${1:-}" flag="${2:-}"
  [[ -n "$name" ]] || die "usage: sage logs <name> [-f|--clear]"
  ensure_init
  local logfile="$LOGS_DIR/$name.log"

  if [[ "$flag" == "--clear" ]]; then
    > "$logfile" 2>/dev/null
    ok "cleared logs for $name"
    return
  fi

  [[ -f "$logfile" ]] || die "no logs for '$name'"
  [[ "$flag" == "-f" ]] && tail -f "$logfile" || tail -50 "$logfile"
}

# ═══════════════════════════════════════════════
# sage attach [name]
# ═══════════════════════════════════════════════
cmd_attach() {
  local name="${1:-}"
  [[ -n "$name" ]] && tmux select-window -t "$TMUX_SESSION:$name" 2>/dev/null
  tmux attach -t "$TMUX_SESSION" 2>/dev/null || die "tmux session not running"
}

# ═══════════════════════════════════════════════
# sage ls
# ═══════════════════════════════════════════════
cmd_ls() {
  ensure_init
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local n=$(basename "$d")
    [[ "$n" == .* ]] && continue
    echo "$n"
  done
}

# ═══════════════════════════════════════════════
# sage rm <name>
# ═══════════════════════════════════════════════
cmd_rm() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "usage: sage rm <name>"
  ensure_init; agent_exists "$name"
  stop_agent "$name" 2>/dev/null || true
  rm -rf "$AGENTS_DIR/$name"
  rm -f "$LOGS_DIR/$name.log"
  ok "removed '$name'"
}

# ═══════════════════════════════════════════════
# sage clean
# ═══════════════════════════════════════════════
cmd_clean() {
  ensure_init
  # Clean up temp files, stale pid files, empty replies
  find "$AGENTS_DIR" -name ".pid" -exec sh -c 'kill -0 $(cat "$1") 2>/dev/null || rm -f "$1"' _ {} \;
  find /tmp -name "sage-*" -mmin +60 -delete 2>/dev/null || true
  find "$AGENTS_DIR" -path "*/replies/*.json" -mmin +60 -delete 2>/dev/null || true
  ok "cleaned up stale files"
}

# ═══════════════════════════════════════════════
# sage wait <name> [--timeout <sec>]
# ═══════════════════════════════════════════════
cmd_wait() {
  local name="" timeout=0 poll_interval=5

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --timeout|-t) timeout="$2"; shift 2 ;;
      -*)           die "unknown flag: $1" ;;
      *)            name="$1"; shift ;;
    esac
  done

  [[ -n "$name" ]] || die "usage: sage wait <name> [--timeout <sec>]"
  ensure_init; agent_exists "$name"

  # Check agent is running
  agent_pid "$name" >/dev/null 2>&1 || die "$name is not running"

  local logfile="$LOGS_DIR/$name.log"
  local start_time=$SECONDS
  # Record current log length — only watch lines added after now
  local log_offset=$(wc -l < "$logfile" 2>/dev/null || echo 0)

  info "waiting for $name to complete... (Ctrl-C to detach)"
  [[ $timeout -gt 0 ]] && info "timeout: ${timeout}s"

  while true; do
    # Get only new log lines since we started waiting
    local new_lines=$(tail -n +$((log_offset + 1)) "$logfile" 2>/dev/null)

    # Show new lines as progress
    if [[ -n "$new_lines" ]]; then
      local new_count=$(echo "$new_lines" | wc -l)
      log_offset=$((log_offset + new_count))
      echo "$new_lines" | while IFS= read -r line; do
        [[ -n "$line" ]] && echo -e "  ${DIM}${line}${NC}"
      done
    fi

    # Check for completion marker in NEW lines only
    if echo "$new_lines" | grep -qE "finished|DONE|completed" 2>/dev/null; then
      # Verify no active CLI process under the runner
      local pid
      if pid=$(agent_pid "$name"); then
        local cli_running=$(ps --ppid "$pid" -o comm= 2>/dev/null | grep -cE "cline|claude|node" || true)
        if [[ "$cli_running" -eq 0 ]]; then
          echo ""
          ok "$name completed"

          # Show workspace contents
          local ws="$AGENTS_DIR/$name/workspace"
          local file_count=$(find "$ws" -maxdepth 1 -type f 2>/dev/null | wc -l)
          if [[ $file_count -gt 0 ]]; then
            echo ""
            printf "  ${BOLD}Workspace:${NC} %s file(s)\n" "$file_count"
            find "$ws" -maxdepth 1 -type f -printf "    %f\n" 2>/dev/null
          fi
          echo ""
          return 0
        fi
      else
        echo ""
        warn "$name is no longer running"
        return 1
      fi
    fi

    # Timeout check
    if [[ $timeout -gt 0 && $((SECONDS - start_time)) -ge $timeout ]]; then
      echo ""
      die "timeout after ${timeout}s (agent still running — use sage logs $name -f to monitor)"
    fi

    sleep "$poll_interval"
  done
}

# ═══════════════════════════════════════════════
# sage steer <name> <message> [--restart]
# ═══════════════════════════════════════════════
cmd_steer() {
  local name="" message="" do_restart=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --restart) do_restart=true; shift ;;
      --kill)    do_restart=true; shift ;;  # legacy alias
      -*)        die "unknown flag: $1" ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        elif [[ -z "$message" ]]; then
          message="$1"
        else
          message="$message $1"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$name" && -n "$message" ]] || die "usage: sage steer <name> <message> [--restart]"
  ensure_init; agent_exists "$name"

  local agent_dir="$AGENTS_DIR/$name"
  local steer_file="$agent_dir/steer.md"

  if [[ "$do_restart" == true ]]; then
    # Find the in-flight task to re-queue
    local inflight_task=""
    local results_dir="$agent_dir/results"
    if [[ -d "$results_dir" ]]; then
      for sf in $(ls -t "$results_dir"/*.status.json 2>/dev/null); do
        local st=$(jq -r '.status' "$sf" 2>/dev/null)
        if [[ "$st" == "running" ]]; then
          inflight_task=$(jq -r '.id' "$sf")
          break
        fi
      done
    fi

    # 1. Stop all children first (cascade)
    local children
    children=$(agent_children "$name")
    if [[ -n "$children" ]]; then
      info "stopping child agents..."
      while IFS= read -r child; do
        cmd_stop "$child" 2>/dev/null && info "  stopped $child" || true
      done <<< "$children"
    fi

    # 2. Stop the agent
    info "stopping $name..."
    cmd_stop "$name" 2>/dev/null || true

    # 3. Write steering context
    printf "## ⚠️ CORRECTION FROM SUPERVISOR ($(date '+%H:%M:%S'))\n\n%s\n\n---\n\n" "$message" > "$steer_file"

    # 4. Mark in-flight task as queued again
    if [[ -n "$inflight_task" && -f "$results_dir/${inflight_task}.status.json" ]]; then
      jq '.status="queued" | .started_at=null | .finished_at=null' \
        "$results_dir/${inflight_task}.status.json" > "$results_dir/${inflight_task}.status.json.tmp" \
        && mv "$results_dir/${inflight_task}.status.json.tmp" "$results_dir/${inflight_task}.status.json"

      # Re-queue the original message from result file or reconstruct
      local result_file="$results_dir/${inflight_task}.result.json"
      # Find original task payload from logs
      local original_payload
      original_payload=$(grep "$inflight_task" "$LOGS_DIR/$name.log" 2>/dev/null | grep "←" | head -1 | sed 's/.*← [^:]*: //' || echo "")

      if [[ -n "$original_payload" ]]; then
        # Re-queue with the original payload
        cat > "$agent_dir/inbox/${inflight_task}.json" <<MSGEOF
{"id":"${inflight_task}","from":"cli","payload":${original_payload},"ts":$(date +%s),"requeued":true}
MSGEOF
        info "re-queued task $inflight_task with steering context"
      fi
    fi

    # 5. Restart
    cmd_start "$name"
    ok "agent restarted with steering: $message"
    if [[ -n "$children" ]]; then
      info "children were stopped — $name will re-create them if needed"
    fi
  else
    # Soft steer: write context that gets picked up on next invocation
    mkdir -p "$(dirname "$steer_file")"
    printf "\n## ⚠️ STEERING UPDATE ($(date '+%H:%M:%S'))\n\n%s\n" "$message" >> "$steer_file"

    # Also send as a message so agent processes it
    export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
    source "$TOOLS_DIR/common.sh"
    local payload
    payload=$(jq -n --arg m "$message" '{priority:"high",type:"steer",text:$m}')
    local task_id
    task_id=$(send_msg "$name" "$payload")
    ok "steering sent to $name (task: $task_id)"
    info "steer.md updated — will be included in next invocation"
    info "use --restart to stop current task, cascade children, and retry"
  fi
}

# ═══════════════════════════════════════════════
# sage tasks [name]
# ═══════════════════════════════════════════════
cmd_tasks() {
  local name="${1:-}"
  ensure_init
  set +e

  local now=$(date +%s)
  local found=0

  printf "\n${BOLD}  ⚡ Tasks${NC}\n\n"
  printf "  ${DIM}%-20s %-12s %-10s %-10s %s${NC}\n" "TASK" "AGENT" "STATUS" "ELAPSED" "FROM"

  # Search specific agent or all agents
  local search_dirs=()
  if [[ -n "$name" ]]; then
    agent_exists "$name"
    search_dirs=("$AGENTS_DIR/$name/results")
  else
    for d in "$AGENTS_DIR"/*/results; do
      [[ -d "$d" ]] && search_dirs+=("$d")
    done
  fi

  for results_dir in "${search_dirs[@]}"; do
    [[ -d "$results_dir" ]] || continue
    local agent_name=$(basename "$(dirname "$results_dir")")
    [[ "$agent_name" == .* ]] && continue

    for status_file in $(ls -t "$results_dir"/*.status.json 2>/dev/null | head -20); do
      [[ -f "$status_file" ]] || continue
      ((found++))

      local task_id=$(jq -r '.id' "$status_file")
      local status=$(jq -r '.status' "$status_file")
      local from=$(jq -r '.from' "$status_file")
      local queued_at=$(jq -r '.queued_at // 0' "$status_file")
      local finished_at=$(jq -r '.finished_at // 0' "$status_file")

      local elapsed
      if [[ "$finished_at" != "null" && "$finished_at" != "0" ]]; then
        elapsed="$(( finished_at - queued_at ))s"
      else
        elapsed="$(( now - queued_at ))s"
      fi

      local status_color
      case "$status" in
        done)    status_color="$GREEN" ;;
        running) status_color="$YELLOW" ;;
        queued)  status_color="$DIM" ;;
        failed)  status_color="$RED" ;;
        *)       status_color="$NC" ;;
      esac

      printf "  %-20s %-12s ${status_color}%-10s${NC} %-10s %s\n" \
        "$task_id" "$agent_name" "$status" "$elapsed" "$from"
    done
  done

  [[ $found -eq 0 ]] && printf "  ${DIM}no tasks${NC}\n"
  printf "\n"
}

# ═══════════════════════════════════════════════
# sage result <task-id>
# ═══════════════════════════════════════════════
cmd_result() {
  local task_id="${1:-}"
  [[ -n "$task_id" ]] || die "usage: sage result <task-id>"
  ensure_init

  # Search all agents for this task
  for results_dir in "$AGENTS_DIR"/*/results; do
    [[ -d "$results_dir" ]] || continue
    local status_file="$results_dir/${task_id}.status.json"
    local result_file="$results_dir/${task_id}.result.json"

    if [[ -f "$status_file" ]]; then
      local status=$(jq -r '.status' "$status_file")
      local agent_name=$(basename "$(dirname "$results_dir")")

      if [[ "$status" == "done" && -f "$result_file" ]]; then
        cat "$result_file"
      elif [[ "$status" == "done" ]]; then
        # No result file — check logs for the output
        echo "{\"status\":\"done\",\"agent\":\"$agent_name\",\"note\":\"task completed — check sage logs $agent_name for output\"}"
      elif [[ "$status" == "running" ]]; then
        echo "{\"status\":\"running\",\"agent\":\"$agent_name\",\"hint\":\"use sage peek $agent_name to see progress\"}"
      else
        cat "$status_file"
      fi
      return 0
    fi
  done

  die "task '$task_id' not found"
}

# ═══════════════════════════════════════════════
# sage peek <name> [--lines N]
# ═══════════════════════════════════════════════
cmd_peek() {
  local name="" lines=30

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lines|-n) lines="$2"; shift 2 ;;
      -*)         die "unknown flag: $1" ;;
      *)          name="$1"; shift ;;
    esac
  done

  [[ -n "$name" ]] || die "usage: sage peek <name> [--lines N]"
  ensure_init; agent_exists "$name"

  # Check if tmux window exists
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null || die "tmux session not running"
  tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${name}$" || die "no tmux window for '$name'"

  # Capture pane content
  local content
  content=$(tmux capture-pane -t "$TMUX_SESSION:$name" -p -S -"$lines" 2>/dev/null) || die "failed to capture pane for '$name'"

  # Also check workspace
  local ws="$AGENTS_DIR/$name/workspace"
  local file_count=$(find "$ws" -maxdepth 1 -type f 2>/dev/null | wc -l)

  printf "\n${BOLD}  ⚡ peek: %s${NC}\n\n" "$name"

  # Show live CLI output if agent is currently running a task
  local live_output="$AGENTS_DIR/$name/.live_output"
  if agent_pid "$name" >/dev/null 2>&1 && [[ -f "$live_output" ]]; then
    local live_size=$(wc -c < "$live_output" 2>/dev/null || echo 0)
    if [[ "$live_size" -gt 0 ]]; then
      printf "  ${BOLD}Live output:${NC}\n"
      tail -"$lines" "$live_output" | while IFS= read -r line; do
        printf "  ${DIM}%s${NC}\n" "$line"
      done
      echo ""
    fi
  fi

  # Show pane content (runner logs)
  printf "  ${BOLD}Runner log:${NC}\n"
  echo "$content" | grep -v '^$' | tail -"$lines" | while IFS= read -r line; do
    printf "  %s\n" "$line"
  done

  if [[ $file_count -gt 0 ]]; then
    printf "\n  ${BOLD}Workspace:${NC} %s file(s)\n" "$file_count"
    find "$ws" -maxdepth 2 -type f -printf "    %TH:%TM  %8s  %P\n" 2>/dev/null | sort -r | head -15
  fi
  echo ""
}

# ═══════════════════════════════════════════════
# sage inbox [--json] [--clear]
# ═══════════════════════════════════════════════
cmd_inbox() {
  local format="pretty" do_clear=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  format="json"; shift ;;
      --clear) do_clear=true; shift ;;
      -*)      die "unknown flag: $1" ;;
      *)       shift ;;
    esac
  done

  ensure_init
  local inbox="$AGENTS_DIR/.cli/inbox"
  mkdir -p "$inbox"

  if [[ "$do_clear" == true ]]; then
    local count=$(find "$inbox" -name "*.json" 2>/dev/null | wc -l)
    rm -f "$inbox"/*.json
    ok "cleared $count message(s)"
    return
  fi

  local msg_count=0
  for msg_file in $(ls -t "$inbox"/*.json 2>/dev/null); do
    [[ -f "$msg_file" ]] || continue
    ((msg_count++))

    if [[ "$format" == "json" ]]; then
      cat "$msg_file"
      echo ""
    else
      local from=$(jq -r '.from // "unknown"' "$msg_file")
      local ts=$(jq -r '.ts // 0' "$msg_file")
      local status=$(jq -r '.payload.status // "—"' "$msg_file")
      local result=$(jq -r '.payload.result // .payload.text // "—"' "$msg_file" | head -c 200)
      local time_str=$(date -d "@$ts" '+%H:%M:%S' 2>/dev/null || echo "—")

      printf "\n  ${BOLD}[%s]${NC} from ${CYAN}%s${NC} — status: ${GREEN}%s${NC}\n" "$time_str" "$from" "$status"
      printf "  %s\n" "$result"
    fi
  done

  if [[ $msg_count -eq 0 ]]; then
    printf "\n  ${DIM}no messages in inbox${NC}\n"
  else
    printf "\n  ${DIM}%d message(s) — use --clear to remove${NC}\n" "$msg_count"
  fi
  echo ""
}

# ═══════════════════════════════════════════════
# sage trace [--tree] [--clear] [-n N]
# ═══════════════════════════════════════════════
cmd_trace() {
  local mode="timeline" limit=50 do_clear=false agent_filter=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tree)  mode="tree"; shift ;;
      --clear) do_clear=true; shift ;;
      -n)      limit="$2"; shift 2 ;;
      -*)      die "unknown flag: $1" ;;
      *)       agent_filter="$1"; shift ;;
    esac
  done

  ensure_init
  local tracefile="$SAGE_HOME/trace.jsonl"

  if [[ "$do_clear" == true ]]; then
    rm -f "$tracefile"
    ok "trace cleared"
    return
  fi

  [[ -f "$tracefile" ]] || { printf "\n  ${DIM}no trace data — run some tasks first${NC}\n\n"; return; }

  # Filter trace to specific agent (matches from, to, or agent fields)
  local trace_data
  if [[ -n "$agent_filter" ]]; then
    trace_data=$(grep -E "\"(from|to|agent)\":\"$agent_filter\"" "$tracefile" | tail -"$limit")
  else
    trace_data=$(tail -"$limit" "$tracefile")
  fi

  [[ -n "$trace_data" ]] || { printf "\n  ${DIM}no trace data for '$agent_filter'${NC}\n\n"; return; }

  if [[ "$mode" == "tree" ]]; then
    # Build task tree: group by root task
    printf "\n${BOLD}  ⚡ Trace (tree)${NC}"
    [[ -n "$agent_filter" ]] && printf " ${DIM}(agent: $agent_filter)${NC}"
    printf "\n\n"

    local send_events done_events
    send_events=$(echo "$trace_data" | grep '"type":"send"')
    done_events=$(echo "$trace_data" | grep '"type":"done"')

    # Find root tasks (from=cli or from not in any agent's task)
    echo "$send_events" | while IFS= read -r event; do
      [[ -z "$event" ]] && continue
      local from=$(echo "$event" | jq -r '.from')
      local to=$(echo "$event" | jq -r '.to')
      local task_id=$(echo "$event" | jq -r '.task_id')
      local text=$(echo "$event" | jq -r '.text' | head -c 50)

      # Check if this is a root task (from cli or from a non-agent)
      if [[ "$from" == "cli" || "$from" == ".cli" ]]; then
        # Root task — find elapsed
        local elapsed=$(echo "$done_events" | grep "\"$task_id\"" | jq -r '.elapsed // "?"' | tail -1)
        local status_icon="⏳"
        [[ "$elapsed" != "?" && -n "$elapsed" ]] && status_icon="✓"
        printf "  ${BOLD}${task_id}${NC} $from → $to \"$text\" (${elapsed}s) $status_icon\n"

        # Find child tasks (sent by $to)
        echo "$send_events" | while IFS= read -r child_event; do
          [[ -z "$child_event" ]] && continue
          local child_from=$(echo "$child_event" | jq -r '.from')
          local child_to=$(echo "$child_event" | jq -r '.to')
          local child_id=$(echo "$child_event" | jq -r '.task_id')
          local child_text=$(echo "$child_event" | jq -r '.text' | head -c 40)

          if [[ "$child_from" == "$to" ]]; then
            local child_elapsed=$(echo "$done_events" | grep "\"$child_id\"" | jq -r '.elapsed // "?"' | tail -1)
            local child_icon="⏳"
            [[ "$child_elapsed" != "?" && -n "$child_elapsed" ]] && child_icon="✓"
            printf "    ├─ ${DIM}${child_id}${NC} $child_from → $child_to \"$child_text\" (${child_elapsed}s) $child_icon\n"
          fi
        done
      fi
    done
    echo ""

  else
    # Timeline mode — chronological
    printf "\n${BOLD}  ⚡ Trace${NC}"
    [[ -n "$agent_filter" ]] && printf " ${DIM}(agent: $agent_filter)${NC}"
    printf "\n\n"
    printf "  ${DIM}%-10s %-8s %-20s %-22s %s${NC}\n" "TIME" "TYPE" "FLOW" "TASK" "INFO"

    echo "$trace_data" | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ts type agent from to task_id text elapsed
      ts=$(echo "$line" | jq -r '.ts')
      type=$(echo "$line" | jq -r '.type')
      task_id=$(echo "$line" | jq -r '.task_id // ""')

      local time_str=$(date -d "@$ts" '+%H:%M:%S' 2>/dev/null || echo "—")

      case "$type" in
        send)
          from=$(echo "$line" | jq -r '.from')
          to=$(echo "$line" | jq -r '.to')
          text=$(echo "$line" | jq -r '.text' | head -c 40)
          printf "  %-10s ${CYAN}%-8s${NC} %-20s %-22s %s\n" "$time_str" "send" "$from → $to" "$task_id" "\"$text\""
          ;;
        start)
          agent=$(echo "$line" | jq -r '.agent')
          from=$(echo "$line" | jq -r '.from')
          printf "  %-10s ${YELLOW}%-8s${NC} %-20s %-22s %s\n" "$time_str" "start" "$agent" "$task_id" "from $from"
          ;;
        done)
          agent=$(echo "$line" | jq -r '.agent')
          elapsed=$(echo "$line" | jq -r '.elapsed // "?"')
          printf "  %-10s ${GREEN}%-8s${NC} %-20s %-22s %s\n" "$time_str" "done" "$agent ✓" "$task_id" "${elapsed}s"
          ;;
      esac
    done
    echo ""
  fi
}

# ═══════════════════════════════════════════════
# sage tool {add|ls}
# ═══════════════════════════════════════════════
cmd_tool() {
  case "${1:-}" in
    add) [[ -n "${2:-}" && -n "${3:-}" ]] || die "usage: sage tool add <name> <path>"
         cp "$3" "$TOOLS_DIR/$2.sh"; chmod +x "$TOOLS_DIR/$2.sh"; ok "tool '$2' registered" ;;
    ls)  for t in "$TOOLS_DIR"/*.sh; do [[ -f "$t" ]] && basename "$t" .sh; done ;;
    *)   die "usage: sage tool {add|ls}" ;;
  esac
}

# ═══════════════════════════════════════════════
# sage help
# ═══════════════════════════════════════════════
cmd_help() {
  cat << 'EOF'

  ⚡ sage — Simple Agent Engine

  USAGE
    sage <command> [args]

  AGENTS
    init [--force]              Initialize sage (~/.sage/)
    create <name> [flags]       Create agent (--runtime bash|cline|claude-code, --model <m>)
    start [name|--all]          Start agent(s) in tmux
    stop [name|--all]           Stop agent(s)
    restart [name|--all]        Restart agent(s)
    status                      Show all agents
    ls                          List agent names
    rm <name>                   Remove agent
    clean                       Clean up stale files

  MESSAGING
    send <to> <message|@file>     Fire-and-forget (returns task ID)
    call <to> <message|@file> [s]  Send and wait for response (default: 60s)
    tasks [name]                List tasks with status
    result <task-id>            Get task result
    wait <name> [--timeout N]   Wait for agent to finish (long-running tasks)
    peek <name> [--lines N]     See what agent is doing (tmux pane + workspace)
    steer <name> <msg> [--restart] Course-correct a running agent
    inbox [--json] [--clear]    View/clear messages sent to you (.cli)

  DEBUG
    logs <name> [-f|--clear]    View/tail/clear agent logs
    trace [name] [--tree] [-n N]  Show agent interaction trace
    attach [name]               Attach to tmux session

  TOOLS
    tool add <name> <path>      Register a tool
    tool ls                     List tools

  RUNTIMES
    bash          Bash handler script (default)
    cline         Cline CLI code assistant
    claude-code   Claude Code CLI (supports Bedrock)

  LONG-RUNNING TASKS
    sage send orch 'Build the entire app'      # fire & forget (non-blocking)
    sage tasks orch                      # check status
    sage peek orch                       # see what it's doing
    sage steer orch "Use REST not GraphQL"  # course-correct
    sage steer orch "Start over" --restart # kill orch + children, re-run task
    sage result <task-id>                # get result when done

EOF
}

# ═══ Main ═══
case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  create)  shift; cmd_create "$@" ;;
  start)   cmd_start "${2:-}" ;;
  stop)    cmd_stop "${2:-}" ;;
  restart) cmd_restart "${2:-}" ;;
  status)  cmd_status ;;
  send)    cmd_send "${2:-}" "${3:-}" ;;
  call)    cmd_call "${2:-}" "${3:-}" "${4:-}" ;;
  tasks)   cmd_tasks "${2:-}" ;;
  result)  cmd_result "${2:-}" ;;
  steer)   shift; cmd_steer "$@" ;;
  wait)    shift; cmd_wait "$@" ;;
  peek)    shift; cmd_peek "$@" ;;
  inbox)   shift; cmd_inbox "$@" ;;
  logs)    cmd_logs "${2:-}" "${3:-}" ;;
  trace)   shift; cmd_trace "$@" ;;
  attach)  cmd_attach "${2:-}" ;;
  ls)      cmd_ls ;;
  rm)      cmd_rm "${2:-}" ;;
  clean)   cmd_clean ;;
  tool)    shift; cmd_tool "$@" ;;
  help|-h|--help|"") cmd_help ;;
  *)       die "unknown command: $1. Run: sage help" ;;
esac
