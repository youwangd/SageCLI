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

send_msg() {
  local to="$1" payload="$2"
  local msg_id="$(date +%s%N)-$$-$RANDOM"
  local me="${SAGE_AGENT_NAME:-cli}"
  local inbox="$AGENTS_DIR/$to/inbox"
  # .cli is a special pseudo-agent for sage call — accept it as a target
  if [[ "$to" == ".cli" ]]; then
    mkdir -p "$AGENTS_DIR/.cli/inbox"
    inbox="$AGENTS_DIR/.cli/inbox"
  fi
  [[ -d "$inbox" ]] || { echo "error: agent '$to' not found" >&2; return 1; }
  cat > "$inbox/${msg_id}.json" <<MSGEOF
{"id":"$msg_id","from":"$me","payload":$payload,"ts":$(date +%s)}
MSGEOF
}

call_agent() {
  local to="$1" payload="$2" timeout="${3:-60}"
  local msg_id="$(date +%s%N)-$$-$RANDOM"
  local me="${SAGE_AGENT_NAME:-cli}"
  local reply_dir="$AGENTS_DIR/${me}/replies"
  mkdir -p "$reply_dir"
  local inbox="$AGENTS_DIR/$to/inbox"
  [[ -d "$inbox" ]] || { echo "error: agent '$to' not found" >&2; return 1; }
  cat > "$inbox/${msg_id}.json" <<MSGEOF
{"id":"$msg_id","from":"$me","payload":$payload,"reply_dir":"$reply_dir","ts":$(date +%s)}
MSGEOF
  local deadline=$((SECONDS + timeout))
  while [[ $SECONDS -lt $deadline ]]; do
    if [[ -f "$reply_dir/${msg_id}.json" ]]; then
      cat "$reply_dir/${msg_id}.json"
      rm "$reply_dir/${msg_id}.json"
      return 0
    fi
    sleep 0.3
  done
  echo "error: timeout waiting for reply from '$to'" >&2
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
  local task=$(echo "$msg" | jq -r '.payload.task // .payload.text // (.payload | tostring)' 2>/dev/null)
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
sage send $from '{\"status\":\"done\",\"agent\":\"$name\",\"result\":\"<brief summary>\"}'"
  fi

  # Write prompt to temp file
  local prompt_file=$(mktemp /tmp/sage-cline-XXXXX.txt)
  cat > "$prompt_file" << PROMPT
$(cat "$instructions" 2>/dev/null)

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

  output=$(cline "${cline_args[@]}" "$(cat "$prompt_file")" 2>&1) || true
  rm -f "$prompt_file"

  log "cline finished: $(echo "$output" | tail -1 | head -c 120)"

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
  local task=$(echo "$msg" | jq -r '.payload.task // .payload.text // (.payload | tostring)' 2>/dev/null)
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
sage send $from '{\"status\":\"done\",\"agent\":\"$name\",\"result\":\"<brief summary>\"}'"
  fi

  # Write prompt to temp file
  local prompt_file=$(mktemp /tmp/sage-claude-XXXXX.txt)
  cat > "$prompt_file" << PROMPT
$(cat "$instructions" 2>/dev/null)

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

  output=$(cat "$prompt_file" | claude "${claude_args[@]}" 2>&1) || true
  rm -f "$prompt_file"

  log "claude-code finished: $(echo "$output" | tail -1 | head -c 120)"

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
    log "← $(echo "$msg" | jq -r '.from'): $(echo "$msg" | jq -c '.payload' | head -c 100)"
    runtime_inject "$AGENT_NAME" "$msg"
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
sage send <agent-name> '{"task":"description","data":"..."}'

# See who's running
sage status

# Create a sub-agent (if you need to delegate)
sage create <name> --runtime $runtime
sage start <name>
sage send <name> '{"task":"..."}'

# Send and wait for a response (sync, 60s default timeout)
sage call <name> '{"task":"..."}' 120

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
- If you need clarification, use \`sage send <from> '{"question":"..."}'\`
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

    printf "  %-16s %-12s ${status_color}%-10s${NC} %-8s %-6s %s\n" \
      "$name" "$runtime" "$status_text" "$pid_text" "$inbox_count" "$last_active"
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
  local to="${1:-}" payload="${2:-}"
  [[ -n "$to" && -n "$payload" ]] || die "usage: sage send <agent> '<json_payload>'"
  ensure_init

  # Allow sending to any agent or .cli
  if [[ "$to" != ".cli" ]]; then
    agent_exists "$to"
  fi

  export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
  source "$TOOLS_DIR/common.sh"

  if ! echo "$payload" | jq . >/dev/null 2>&1; then
    payload="$(jq -n --arg t "$payload" '{text:$t}')"
  fi

  send_msg "$to" "$payload"
  ok "sent to $to"
}

# ═══════════════════════════════════════════════
# sage call <to> <payload> [timeout]
# ═══════════════════════════════════════════════
cmd_call() {
  local to="${1:-}" payload="${2:-}" timeout="${3:-60}"
  [[ -n "$to" && -n "$payload" ]] || die "usage: sage call <agent> '<json_payload>' [timeout]"
  ensure_init; agent_exists "$to"

  # Use the agent's own name if running inside an agent, otherwise .cli
  local caller="${SAGE_AGENT_NAME:-.cli}"
  mkdir -p "$AGENTS_DIR/$caller/replies"
  export SAGE_AGENT_NAME="$caller"
  source "$TOOLS_DIR/common.sh"

  if ! echo "$payload" | jq . >/dev/null 2>&1; then
    payload="$(jq -n --arg t "$payload" '{text:$t}')"
  fi

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
    send <to> <payload>         Fire-and-forget message
    call <to> <payload> [sec]   Send and wait for response (default: 60s)

  DEBUG
    logs <name> [-f|--clear]    View/tail/clear agent logs
    attach [name]               Attach to tmux session

  TOOLS
    tool add <name> <path>      Register a tool
    tool ls                     List tools

  RUNTIMES
    bash          Bash handler script (default)
    cline         Cline CLI code assistant
    claude-code   Claude Code CLI (supports Bedrock)

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
  logs)    cmd_logs "${2:-}" "${3:-}" ;;
  attach)  cmd_attach "${2:-}" ;;
  ls)      cmd_ls ;;
  rm)      cmd_rm "${2:-}" ;;
  clean)   cmd_clean ;;
  tool)    shift; cmd_tool "$@" ;;
  help|-h|--help|"") cmd_help ;;
  *)       die "unknown command: $1. Run: sage help" ;;
esac
