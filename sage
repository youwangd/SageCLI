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
agent_exists() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid agent name '$1'"
  [[ -d "$AGENTS_DIR/$1" ]] || die "agent '$1' not found"
}

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

  mkdir -p "$AGENTS_DIR" "$TOOLS_DIR" "$RUNTIMES_DIR" "$LOGS_DIR" "$AGENTS_DIR/.cli/replies" "$SAGE_HOME/tasks" "$SAGE_HOME/plans"

  # ── Install task templates ──
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -d "$script_dir/tasks" ]]; then
    cp "$script_dir/tasks"/*.md "$SAGE_HOME/tasks/" 2>/dev/null || true
  fi

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
  # Validate target name (prevent path traversal in agent-to-agent messaging)
  if [[ "$to" != ".cli" && ! "$to" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "error: invalid agent name '$to'" >&2; return 1
  fi
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
  # Validate target name
  if [[ ! "$to" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "error: invalid agent name '$to'" >&2; return 1
  fi
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
      rm -f "$reply_dir/${task_id}.json"
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
    local _rptmp=$(mktemp "$reply_dir/.tmp.XXXXXX")
    echo "$result" > "$_rptmp" && mv "$_rptmp" "$reply_dir/${msg_id}.json" || rm -f "$_rptmp"
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
    curl -s --max-time 120 https://api.anthropic.com/v1/messages \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$(jq -n --arg m "$model" --arg p "$prompt" \
        '{model:$m,max_tokens:4096,messages:[{role:"user",content:$p}]}')" \
      | jq -r '.content[0].text'
  elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    curl -s --max-time 120 https://api.openai.com/v1/chat/completions \
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

  # Remove steer file after reading (so it doesn't affect subsequent tasks)
  [[ -f "$steer_file" ]] && rm -f "$steer_file"

  log "invoking cline..."
  local output
  cd "$workdir"

  local cline_args=(--act -c "$workdir")
  [[ -n "$model" ]] && cline_args+=(-m "$model")

  local live_output="$agent_dir/.live_output"
  > "$live_output"

  # Use --json for real-time event streaming (like claude's stream-json)
  cd "$workdir"
  cline "${cline_args[@]}" --json "$(cat "$prompt_file")" 2>&1 | while IFS= read -r line; do
    local say_type
    say_type=$(echo "$line" | jq -r '.say // .type // empty' 2>/dev/null)
    case "$say_type" in
      text|completion_result)
        local text
        text=$(echo "$line" | jq -r '.text // empty' 2>/dev/null)
        if [[ -n "$text" ]]; then
          echo "$text"
          echo "$text" >> "$live_output"
        fi
        ;;
      tool)
        local tool_name
        tool_name=$(echo "$line" | jq -r '.text // empty' 2>/dev/null | jq -r '.tool // empty' 2>/dev/null)
        [[ -n "$tool_name" ]] && printf "\033[36m  → %s\033[0m\n" "$tool_name"
        ;;
      api_req_started)
        printf "\033[2m  ⋯ thinking...\033[0m\n"
        ;;
      task_started)
        printf "\033[32m  ✓ task started\033[0m\n"
        ;;
    esac
  done

  output=$(cat "$live_output")
  rm -f "$prompt_file"

  log "cline finished: $(echo "$output" | tail -1 | head -c 120)"

  # Write result for task tracking
  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    local _rtmp=$(mktemp "$results_dir/.tmp.XXXXXX")
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$_rtmp" && mv "$_rtmp" "$results_dir/${msg_id}.result.json" || rm -f "$_rtmp"
  fi

  # Write reply for sync calls
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    local _rptmp=$(mktemp "$reply_dir/.tmp.XXXXXX")
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$(echo "$output" | jq -Rs .)}" > "$_rptmp" && mv "$_rptmp" "$reply_dir/${msg_id}.json" || rm -f "$_rptmp"
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

  # Remove steer file after reading (so it doesn't affect subsequent tasks)
  [[ -f "$steer_file" ]] && rm -f "$steer_file"

  export CLAUDE_CODE_USE_BEDROCK=1

  log "invoking claude-code..."
  local output
  cd "$workdir"

  local claude_args=(-p --output-format text --allowedTools "Bash(*)" "Write(*)" "Read(*)" "Edit(*)")
  [[ -n "$model" ]] && claude_args+=(--model "$model")

  local live_output="$agent_dir/.live_output"
  > "$live_output"

  # Use stream-json + verbose for real-time event streaming
  # Each line is a JSON event — we parse and display meaningful ones live
  cd "$workdir"
  cat "$prompt_file" | claude -p --output-format stream-json --verbose \
    --allowedTools "Bash(*)" "Write(*)" "Read(*)" "Edit(*)" \
    ${model:+--model "$model"} 2>&1 | while IFS= read -r line; do
    local evt=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
    case "$evt" in
      assistant)
        local tools text
        tools=$(echo "$line" | jq -r '[.message.content[]? | select(.type == "tool_use") | .name] | join(", ")' 2>/dev/null)
        text=$(echo "$line" | jq -r '[.message.content[]? | select(.type == "text") | .text] | join("")' 2>/dev/null)
        [[ -n "$tools" ]] && printf "\033[36m  → %s\033[0m\n" "$tools"
        [[ -n "$text" ]] && { echo "$text"; echo "$text" >> "$live_output"; }
        ;;
      result)
        local result_text
        result_text=$(echo "$line" | jq -r '.result // empty' 2>/dev/null)
        [[ -n "$result_text" ]] && { echo "$result_text"; echo "$result_text" >> "$live_output"; }
        ;;
    esac
  done

  output=$(cat "$live_output")
  rm -f "$prompt_file"

  log "claude-code finished: $(echo "$output" | tail -1 | head -c 120)"

  # Write result for task tracking
  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    local _rtmp=$(mktemp "$results_dir/.tmp.XXXXXX")
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$_rtmp" && mv "$_rtmp" "$results_dir/${msg_id}.result.json" || rm -f "$_rtmp"
  fi

  # Write reply for sync calls
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    local _rptmp=$(mktemp "$reply_dir/.tmp.XXXXXX")
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$(echo "$output" | jq -Rs .)}" > "$_rptmp" && mv "$_rptmp" "$reply_dir/${msg_id}.json" || rm -f "$_rptmp"
  fi
}
RTEOF

  # ── Runtime: acp ──
  cat > "$RUNTIMES_DIR/acp.sh" << 'RTEOF'
#!/bin/bash
# Runtime: ACP (Agent Client Protocol) bridge
# Speaks JSON-RPC 2.0 over stdio to any ACP-compatible agent (cline, claude-code, goose, kiro, gemini...)
# Persistent session: first message creates the session, follow-ups steer within the same conversation.

_acp_fifo_in=""
_acp_fifo_out=""
_acp_agent_pid=""
_acp_session_id=""
_acp_fd_w=""
_acp_fd_r=""
_acp_rpc_id=10  # start high to avoid collisions with agent-initiated request ids
_acp_agent_type=""

_acp_send() { echo "$1" >&7; }

_acp_read() {
  local timeout="${1:-90}"
  IFS= read -r -t "$timeout" line <&8 && echo "$line"
}

_acp_cleanup() {
  exec 7>&- 2>/dev/null; exec 8<&- 2>/dev/null
  [[ -n "$_acp_agent_pid" ]] && kill "$_acp_agent_pid" 2>/dev/null && wait "$_acp_agent_pid" 2>/dev/null
  rm -f "$_acp_fifo_in" "$_acp_fifo_out"
  [[ -n "${_acp_tmpdir:-}" ]] && rm -rf "$_acp_tmpdir" 2>/dev/null
  _acp_agent_pid=""
  _acp_session_id=""
}

_acp_start_agent() {
  local agent_dir="$1" name="$2"
  local workdir=$(jq -r '.workdir // "."' "$agent_dir/runtime.json" 2>/dev/null)
  _acp_agent_type=$(jq -r '.acp_agent // "cline"' "$agent_dir/runtime.json" 2>/dev/null)

  # Determine ACP command
  local acp_cmd
  case "$_acp_agent_type" in
    cline)       acp_cmd="cline --acp" ;;
    claude-code) acp_cmd="claude-agent-acp"; export CLAUDE_CODE_USE_BEDROCK=1 ;;
    goose)       acp_cmd="goose --acp" ;;
    kiro)        acp_cmd="kiro --acp" ;;
    gemini)      acp_cmd="gemini --experimental-acp" ;;
    *)           acp_cmd="$_acp_agent_type --acp" ;;
  esac

  local _acp_tmpdir=$(mktemp -d /tmp/sage-acp-XXXXX)
  _acp_fifo_in="$_acp_tmpdir/in"
  _acp_fifo_out="$_acp_tmpdir/out"
  mkfifo "$_acp_fifo_in" "$_acp_fifo_out"

  cd "$workdir"
  $acp_cmd < "$_acp_fifo_in" > "$_acp_fifo_out" 2>/dev/null &
  _acp_agent_pid=$!

  exec 7>"$_acp_fifo_in"
  exec 8<"$_acp_fifo_out"

  # Initialize
  _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$_acp_rpc_id,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{\"fs\":{\"readTextFile\":true,\"writeTextFile\":true},\"terminal\":true},\"clientInfo\":{\"name\":\"sage\",\"version\":\"1.0.0\"}}}"
  ((_acp_rpc_id++))
  local r=$(_acp_read 15)
  local aname=$(echo "$r" | jq -r '.result.agentInfo.name // "unknown"' 2>/dev/null)
  local aver=$(echo "$r" | jq -r '.result.agentInfo.version // "?"' 2>/dev/null)
  log "ACP connected: $aname v$aver"

  # Create session
  _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$_acp_rpc_id,\"method\":\"session/new\",\"params\":{\"workspaceRoots\":[{\"uri\":\"file://$workdir\"}],\"cwd\":\"$workdir\",\"mcpServers\":[]}}"
  ((_acp_rpc_id++))
  r=$(_acp_read 15)
  _acp_session_id=$(echo "$r" | jq -r '.result.sessionId // empty' 2>/dev/null)

  if [[ -z "$_acp_session_id" || "$_acp_session_id" == "null" ]]; then
    log "ACP session creation failed: $(echo "$r" | jq -c '.error' 2>/dev/null)"
    _acp_cleanup
    return 1
  fi
  log "ACP session: $_acp_session_id"
}

_acp_process_events() {
  local prompt_id="$1" live_output="$2"
  local text_buf="" output=""
  local cancel_file="$AGENTS_DIR/$AGENT_NAME/.acp_cancel"

  while true; do
    # Check for cancel signal (from --force) BEFORE reading next event
    if [[ -f "$cancel_file" ]]; then
      rm -f "$cancel_file"
      log "ACP cancel signal received — aborting current task"
      printf "\033[31m  ⚠ cancelled by --force\033[0m\n"
      # Send session/cancel
      _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$_acp_rpc_id,\"method\":\"session/cancel\",\"params\":{\"sessionId\":\"$_acp_session_id\"}}"
      ((_acp_rpc_id++))
      # Kill and restart the ACP agent process for a clean slate
      _acp_cleanup
      _acp_start_agent "$AGENTS_DIR/$AGENT_NAME" "$AGENT_NAME"
      break
    fi

    # Use short read timeout so cancel checks happen frequently
    local event
    IFS= read -r -t 1 event <&8 || true
    if [[ -z "$event" ]]; then
      # No event this cycle — check agent alive
      if [[ -n "$_acp_agent_pid" ]] && ! kill -0 "$_acp_agent_pid" 2>/dev/null; then
        log "ACP agent process died"
        break
      fi
      continue
    fi

    local eid=$(echo "$event" | jq -r '.id // empty' 2>/dev/null)
    local method=$(echo "$event" | jq -r '.method // empty' 2>/dev/null)
    local update=$(echo "$event" | jq -r '.params.update.sessionUpdate // empty' 2>/dev/null)

    # Final response for our prompt
    if [[ "$eid" == "$prompt_id" ]]; then
      if [[ -n "$text_buf" ]]; then
        echo "$text_buf"
        echo "$text_buf" >> "$live_output"
        output+="$text_buf"
        text_buf=""
      fi
      local stop=$(echo "$event" | jq -r '.result.stopReason // "?"' 2>/dev/null)
      printf "\033[32m  ✓ done (%s)\033[0m\n" "$stop"
      break
    fi

    # Process notifications
    case "$update" in
      agent_message_chunk)
        local t=$(echo "$event" | jq -r '.params.update.content.text // empty' 2>/dev/null)
        text_buf+="$t"
        ;;
      tool_call)
        if [[ -n "$text_buf" ]]; then
          echo "$text_buf"; echo "$text_buf" >> "$live_output"; output+="$text_buf"; text_buf=""
        fi
        local title=$(echo "$event" | jq -r '.params.update.title // "tool"' 2>/dev/null)
        printf "\033[36m  → %s\033[0m\n" "$title"
        ;;
      tool_call_update)
        local s=$(echo "$event" | jq -r '.params.update.status // empty' 2>/dev/null)
        [[ "$s" == "completed" ]] && printf "\033[32m  ✓ tool done\033[0m\n"
        [[ "$s" == "failed" ]] && printf "\033[31m  ✗ tool failed\033[0m\n"
        ;;
      plan)
        local entries=$(echo "$event" | jq -r '[.params.update.entries[]? | .content] | join(", ")' 2>/dev/null)
        [[ -n "$entries" ]] && printf "\033[33m  📋 %s\033[0m\n" "$entries"
        ;;
      agent_thought_chunk|usage_update|available_commands_update|current_mode_update) ;;
      *) [[ -n "$update" ]] && printf "\033[2m  [%s]\033[0m\n" "$update" ;;
    esac

    # Handle server-to-client requests
    if [[ -n "$method" && "$method" != "null" ]]; then
      local rid=$(echo "$event" | jq -r '.id // empty' 2>/dev/null)
      [[ -z "$rid" || "$rid" == "null" ]] && continue

      case "$method" in
        session/request_permission)
          printf "\033[33m  🔓 permission → approved\033[0m\n"
          # Claude agent ACP uses outcome object; cline doesn't ask
          _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$rid,\"result\":{\"outcome\":{\"outcome\":\"selected\",\"optionId\":\"allow_always\"}}}"
          ;;
        fs/write_text_file)
          local path=$(echo "$event" | jq -r '.params.path // empty' 2>/dev/null)
          local content=$(echo "$event" | jq -r '.params.content // empty' 2>/dev/null)
          # Security: resolve path and ensure it doesn't escape working directory
          if [[ -n "$path" ]]; then
            local resolved=$(realpath -m "$path" 2>/dev/null || echo "$path")
            local cwd_resolved=$(realpath -m "$(pwd)" 2>/dev/null || pwd)
            if [[ "$resolved" == "$cwd_resolved"* ]]; then
              mkdir -p "$(dirname "$path")" 2>/dev/null; printf '%s' "$content" > "$path"
            else
              log "BLOCKED write to $resolved (outside workspace $cwd_resolved)"
            fi
          fi
          _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$rid,\"result\":{}}"
          ;;
        fs/read_text_file)
          local path=$(echo "$event" | jq -r '.params.path // empty' 2>/dev/null)
          # Security: resolve path and ensure it doesn't escape working directory
          local c=""
          if [[ -n "$path" ]]; then
            local resolved=$(realpath -m "$path" 2>/dev/null || echo "$path")
            local cwd_resolved=$(realpath -m "$(pwd)" 2>/dev/null || pwd)
            if [[ "$resolved" == "$cwd_resolved"* && -f "$path" ]]; then
              c=$(cat "$path" | jq -Rs .)
            elif [[ "$resolved" != "$cwd_resolved"* ]]; then
              log "BLOCKED read from $resolved (outside workspace $cwd_resolved)"
            fi
          fi
          _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$rid,\"result\":{\"text\":${c:-\"\"}}}"
          ;;
        *)
          _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$rid,\"result\":{}}"
          ;;
      esac
    fi
  done
}

runtime_start() {
  local agent_dir="$1" name="$2"
  mkdir -p "$agent_dir/workspace"
  _acp_start_agent "$agent_dir" "$name"
  # Register cleanup on exit
  trap '_acp_cleanup' EXIT
}

runtime_inject() {
  local name="$1" msg="$2"
  local agent_dir="$AGENTS_DIR/$name"
  local task=$(echo "$msg" | jq -r '.payload.text // (.payload | tostring)' 2>/dev/null)
  local from=$(echo "$msg" | jq -r '.from' 2>/dev/null)
  local msg_id=$(echo "$msg" | jq -r '.id' 2>/dev/null)
  local reply_dir=$(echo "$msg" | jq -r '.reply_dir // empty' 2>/dev/null)
  local instructions="$agent_dir/instructions.md"
  local steer_file="$agent_dir/steer.md"
  local live_output="$agent_dir/.live_output"
  > "$live_output"

  # If no ACP session, start one
  if [[ -z "$_acp_session_id" ]]; then
    _acp_start_agent "$agent_dir" "$name"
  fi

  # Build prompt — first message gets instructions, follow-ups are just the task
  local full_prompt="$task"
  if [[ -f "$steer_file" ]]; then
    full_prompt="$(cat "$steer_file")

$full_prompt"
    rm -f "$steer_file"
  fi

  local escaped_prompt=$(echo "$full_prompt" | jq -Rs .)

  log "ACP prompt ($from): $(echo "$task" | head -c 120)"

  local prompt_id=$_acp_rpc_id
  ((_acp_rpc_id++))
  _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$prompt_id,\"method\":\"session/prompt\",\"params\":{\"sessionId\":\"$_acp_session_id\",\"prompt\":[{\"type\":\"text\",\"text\":$escaped_prompt}]}}"

  # Process events — output goes directly to tmux pane (stdout)
  # Text is also accumulated in $live_output file
  _acp_process_events "$prompt_id" "$live_output"

  local output=$(cat "$live_output")
  log "ACP finished: $(echo "$output" | tail -1 | head -c 120)"

  # Write result
  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    local _rtmp=$(mktemp "$results_dir/.tmp.XXXXXX")
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$_rtmp" && mv "$_rtmp" "$results_dir/${msg_id}.result.json" || rm -f "$_rtmp"
  fi

  # Write reply for sync calls
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    local _rptmp=$(mktemp "$reply_dir/.tmp.XXXXXX")
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$(echo "$output" | jq -Rs .)}" > "$_rptmp" && mv "$_rptmp" "$reply_dir/${msg_id}.json" || rm -f "$_rptmp"
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

# Validate runtime name (prevent path traversal)
if [[ ! "$RUNTIME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "error: invalid runtime name '$RUNTIME'" >&2
  exit 1
fi

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
    local task_rc=0
    runtime_inject "$AGENT_NAME" "$msg" || task_rc=$?
    task_elapsed=$(( $(date +%s) - task_start_ts ))

    # Update task status based on runtime exit code
    local final_status="done"
    [[ $task_rc -ne 0 ]] && final_status="failed"
    if [[ -f "$status_file" ]]; then
      jq --arg ts "$(date +%s)" --arg st "$final_status" '.status=$st | .finished_at=($ts|tonumber)' "$status_file" > "${status_file}.tmp" && mv "${status_file}.tmp" "$status_file"
    fi

    # Trace: task done/failed
    echo "{\"ts\":$(date +%s),\"type\":\"done\",\"agent\":\"$AGENT_NAME\",\"task_id\":\"$local_task_id\",\"elapsed\":$task_elapsed,\"status\":\"$final_status\"}" >> "$SAGE_HOME/trace.jsonl" 2>/dev/null
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
  local name="" runtime="bash" model="" parent="" acp_agent="" worktree_branch=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --runtime|-r)   runtime="$2"; shift 2 ;;
      --model|-m)     model="$2"; shift 2 ;;
      --agent|-a)     acp_agent="$2"; shift 2 ;;
      --parent)       parent="$2"; shift 2 ;;
      --worktree|-w)  worktree_branch="$2"; shift 2 ;;
      -*)             die "unknown flag: $1" ;;
      *)              name="$1"; shift ;;
    esac
  done

  [[ -n "$name" ]] || die "usage: sage create <name> [--runtime bash|cline|claude-code|acp] [--agent <agent>] [--model <model>]"

  # Validate agent name: alphanumeric, hyphens, underscores only
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    die "invalid agent name '$name' — use alphanumeric, hyphens, underscores, dots only"
  fi

  # If --agent is specified without --runtime, default to acp
  if [[ -n "$acp_agent" && "$runtime" == "bash" ]]; then
    runtime="acp"
  fi
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

  # Git worktree isolation
  if [[ -n "$worktree_branch" ]]; then
    git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository — --worktree requires a git repo"
    local repo_root
    repo_root=$(git rev-parse --show-toplevel)
    # Check branch doesn't already exist as a worktree
    if git worktree list 2>/dev/null | grep -q "\[$worktree_branch\]"; then
      rm -rf "$agent_dir"
      die "branch '$worktree_branch' already has a worktree"
    fi
    rm -rf "$agent_dir/workspace"
    git worktree add "$agent_dir/workspace" -b "$worktree_branch" >/dev/null 2>&1 || {
      rm -rf "$agent_dir"
      die "failed to create worktree for branch '$worktree_branch'"
    }
  fi

  # Write runtime config
  local wt="false" wb=""
  if [[ -n "$worktree_branch" ]]; then wt="true"; wb="$worktree_branch"; fi
  jq -n \
    --arg rt "$runtime" \
    --arg m "$model" \
    --arg p "$parent" \
    --arg wd "$agent_dir/workspace" \
    --arg aa "$acp_agent" \
    --argjson wt "$wt" \
    --arg wb "$wb" \
    '{runtime:$rt, model:$m, parent:$p, workdir:$wd, acp_agent:$aa, worktree:$wt, worktree_branch:$wb, created:(now|todate)}' \
    > "$agent_dir/runtime.json"

  # Generate instructions for CLI runtimes
  if [[ "$runtime" != "bash" ]]; then
    local rt_display="$runtime"
    [[ "$runtime" == "acp" && -n "$acp_agent" ]] && rt_display="acp ($acp_agent)"
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

  # Kill any stale tmux window with the same name
  tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null || true

  # NOTE: -t "$TMUX_SESSION:" (trailing colon) = next available index
  # Without colon, tmux tries to create at the current active window index → collision
  if ! tmux new-window -t "$TMUX_SESSION:" -n "$name" \
    "bash $SAGE_HOME/runner.sh $AGENTS_DIR/$name; echo '[exited — press enter]'; read" 2>/dev/null; then
    warn "failed to create tmux window for $name"
    return 1
  fi

  # Wait briefly and verify the runner actually started
  sleep 0.5
  if ! agent_pid "$name" >/dev/null 2>&1; then
    # Check if tmux window exists but runner hasn't written PID yet
    sleep 1
    if ! agent_pid "$name" >/dev/null 2>&1; then
      warn "$name: tmux window created but runner failed to start"
      tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null || true
      return 1
    fi
  fi

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
    # No running process — still clean up stale tmux window
    tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null
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
    ((count++)) || true
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
  local to="" message="" force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) force=true; shift ;;
      -*)         die "unknown flag: $1" ;;
      *)
        if [[ -z "$to" ]]; then
          to="$1"
        elif [[ -z "$message" ]]; then
          message="$1"
        else
          message="$message $1"
        fi
        shift
        ;;
    esac
  done

  [[ -n "$to" && -n "$message" ]] || die "usage: sage send <agent> <message|@file> [--force]"
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

  # --force: signal the ACP runtime to cancel the current task
  if [[ "$force" == true ]]; then
    local cancel_file="$AGENTS_DIR/$to/.acp_cancel"
    echo "1" > "$cancel_file"
    info "cancel signal sent — current task will be interrupted"
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
  local to="" message="" timeout="60"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --timeout|-t) timeout="$2"; shift 2 ;;
      -*)           die "unknown flag: $1" ;;
      *)
        if [[ -z "$to" ]]; then
          to="$1"
        elif [[ -z "$message" ]]; then
          message="$1"
        else
          # If third positional looks like a number, treat as timeout (legacy)
          if [[ "$1" =~ ^[0-9]+$ && -z "${2:-}" ]]; then
            timeout="$1"
          else
            message="$message $1"
          fi
        fi
        shift
        ;;
    esac
  done

  [[ -n "$to" && -n "$message" ]] || die "usage: sage call <agent> <message|@file> [timeout] [--timeout N]"
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
  # Validate name to prevent path traversal
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid agent name"
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
  # Clean up git worktree if applicable
  local agent_dir="$AGENTS_DIR/$name"
  if [[ "$(jq -r '.worktree // false' "$agent_dir/runtime.json" 2>/dev/null)" == "true" ]]; then
    git worktree remove "$agent_dir/workspace" --force 2>/dev/null || true
  fi
  rm -rf "$AGENTS_DIR/$name"
  rm -f "$LOGS_DIR/$name.log"
  ok "removed '$name'"
}

# ═══════════════════════════════════════════════
# sage merge <name>
# ═══════════════════════════════════════════════
cmd_merge() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "usage: sage merge <name>"
  ensure_init; agent_exists "$name"
  local agent_dir="$AGENTS_DIR/$name"
  local is_wt branch
  is_wt=$(jq -r '.worktree // false' "$agent_dir/runtime.json" 2>/dev/null)
  [[ "$is_wt" == "true" ]] || die "agent '$name' is not a worktree agent"
  branch=$(jq -r '.worktree_branch' "$agent_dir/runtime.json")
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
  git merge "$branch" --no-edit || die "merge conflict — resolve manually then run: git merge --continue"
  ok "merged branch '$branch' from agent '$name'"
}

# ═══════════════════════════════════════════════
# sage clean
# ═══════════════════════════════════════════════
cmd_clean() {
  ensure_init
  # Clean up stale pid files (where process is no longer running)
  while IFS= read -r -d '' pidfile; do
    local pid_val
    pid_val=$(cat "$pidfile" 2>/dev/null)
    if [[ "$pid_val" =~ ^[0-9]+$ ]] && ! kill -0 "$pid_val" 2>/dev/null; then
      rm -f "$pidfile"
    fi
  done < <(find "$AGENTS_DIR" -name ".pid" -print0 2>/dev/null)
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

    # Check for completion via status files (authoritative) + log heuristics (fallback)
    local any_done=false
    if [[ -d "$AGENTS_DIR/$name/results" ]]; then
      # Check if latest running task is now done
      local latest_status
      latest_status=$(ls -t "$AGENTS_DIR/$name/results/"*.status.json 2>/dev/null | head -1)
      if [[ -n "$latest_status" ]]; then
        local st=$(jq -r '.status' "$latest_status" 2>/dev/null)
        if [[ "$st" == "done" ]]; then
          any_done=true
        fi
      fi
    fi
    # Fallback: check log text for completion markers
    if [[ "$any_done" != true ]] && echo "$new_lines" | grep -qE "finished|DONE|completed" 2>/dev/null; then
      any_done=true
    fi

    if [[ "$any_done" == true ]]; then
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

  for results_dir in ${search_dirs[@]+"${search_dirs[@]}"}; do
    [[ -d "$results_dir" ]] || continue
    local agent_name=$(basename "$(dirname "$results_dir")")
    [[ "$agent_name" == .* ]] && continue

    for status_file in $(ls -t "$results_dir"/*.status.json 2>/dev/null | head -20); do
      [[ -f "$status_file" ]] || continue
      ((found++)) || true

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
    ((msg_count++)) || true

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
# Task template helpers
# ═══════════════════════════════════════════════
TASKS_DIR="$SAGE_HOME/tasks"
PLANS_DIR="$SAGE_HOME/plans"

# Parse YAML frontmatter from a task template
# Usage: _parse_frontmatter <file> <key>
_parse_frontmatter() {
  local file="$1" key="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep -E "^${key}:" | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*#.*//' | tr -d '"' | tr -d "'"
}

# List available task templates with metadata
_list_templates() {
  local tasks_dir="$1"
  for tmpl in "$tasks_dir"/*.md; do
    [[ -f "$tmpl" ]] || continue
    local name=$(basename "$tmpl" .md)
    local desc=$(_parse_frontmatter "$tmpl" "description")
    local rt=$(_parse_frontmatter "$tmpl" "runtime")
    printf "  %-12s %-8s %s\n" "$name" "($rt)" "$desc"
  done
}

# Get template body (everything after the second ---)
_template_body() {
  local file="$1"
  awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$file"
}


# ═══════════════════════════════════════════════
# Goal-driven task loop
# ═══════════════════════════════════════════════
RUNS_DIR="$SAGE_HOME/runs"

_generate_checks() {
  local goal="$1" project_context="$2"

  local prompt="You are generating validation checks for a software task.

Goal: ${goal}

Project context (files in project):
${project_context}

Generate a JSON array of checks to verify this goal is achieved. Each check has:
- \"tier\": \"mechanical\" (shell command) or \"agent\" (needs browser/complex inspection) or \"manual\" (subjective, needs human)
- \"command\": for mechanical tier, the exact shell command to run
- \"expect\": for mechanical tier, \"exit 0\" or \"contains TEXT\"
- \"description\": human-readable description of what this checks

Prefer mechanical checks when possible. Use agent tier only when a shell command truly cannot verify it. Use manual tier only for subjective aesthetics.

IMPORTANT rules:
- Generate the MINIMUM number of checks needed. One good check beats three redundant ones.
- For test suites, a single \"exit 0\" check is sufficient — don't also check output text.
- For \"contains\" expectations, use EXACT text from the tool's actual output format (don't guess).
- Never generate two checks that run the same command.

Return ONLY a valid JSON array, no markdown fences, no explanation."

  # Try Gemini first, then Anthropic, then OpenAI
  if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    curl -s --max-time 60 \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg p "$prompt" '{contents:[{parts:[{text:$p}]}],generationConfig:{temperature:0.1}}')" \
      | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    source "$TOOLS_DIR/llm.sh"
    llm "$prompt"
  elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    source "$TOOLS_DIR/llm.sh"
    llm "$prompt"
  else
    echo "error: no LLM API key set (need GEMINI_API_KEY, ANTHROPIC_API_KEY, or OPENAI_API_KEY)" >&2
    return 1
  fi
}

_run_mechanical_checks() {
  local checks_file="$1" results_file="$2"
  local all_pass=true
  local results="[]"
  local check_items
  check_items=$(jq -c '[.[] | select(.tier == "mechanical")]' "$checks_file")
  local n=$(echo "$check_items" | jq 'length')

  for i in $(seq 0 $((n - 1))); do
    local cmd=$(echo "$check_items" | jq -r ".[$i].command")
    local expect=$(echo "$check_items" | jq -r ".[$i].expect")
    local desc=$(echo "$check_items" | jq -r ".[$i].description")

    local output exit_code=0
    output=$(eval "$cmd" 2>&1) || exit_code=$?

    local status="PASS"
    if [[ "$expect" == "exit 0" && "$exit_code" -ne 0 ]]; then
      status="FAIL"
      all_pass=false
    elif [[ "$expect" == contains\ * ]]; then
      local expected_text="${expect#contains }"
      if ! echo "$output" | grep -qF "$expected_text"; then
        status="FAIL"
        all_pass=false
      fi
    fi

    local trunc_output="${output:0:2000}"
    results=$(echo "$results" | jq \
      --arg d "$desc" --arg s "$status" --arg o "$trunc_output" --arg c "$cmd" --argjson e "$exit_code" \
      '. + [{"description":$d,"status":$s,"exit_code":$e,"output":$o,"command":$c}]')
  done

  echo "$results" > "$results_file"
  [[ "$all_pass" == true ]]
}

_run_validator() {
  local checks_file="$1" output_file="$2" run_dir="$3" stimeout="$4"
  local agent_checks
  agent_checks=$(jq -r '[.[] | select(.tier == "agent")] | .[] | .description' "$checks_file")
  [[ -z "$agent_checks" ]] && { echo "VERDICT: PASS" > "$output_file"; return 0; }

  local agent_name="sage-validator-$(date +%s)"
  local agent_dir="$AGENTS_DIR/$agent_name"
  local tmpl_body
  tmpl_body=$(_template_body "$TASKS_DIR/validate.md")

  cmd_create "$agent_name" --runtime acp --agent claude-code 2>/dev/null
  echo "$tmpl_body" > "$agent_dir/instructions.md"
  cmd_start "$agent_name" 2>/dev/null

  local check_prompt="Please verify these checks independently:\n\n"
  while IFS= read -r line; do
    [[ -n "$line" ]] && check_prompt+="- ${line}\n"
  done <<< "$agent_checks"

  source "$TOOLS_DIR/common.sh"
  local payload
  payload=$(jq -n --arg t "$(echo -e "$check_prompt")" '{text:$t}')
  local task_id
  task_id=$(send_msg "$agent_name" "$payload")

  local deadline=$((SECONDS + stimeout))
  local status_file="$agent_dir/results/${task_id}.status.json"

  while [[ $SECONDS -lt $deadline ]]; do
    if [[ -f "$status_file" ]]; then
      local st
      st=$(jq -r '.status' "$status_file" 2>/dev/null)
      [[ "$st" == "done" || "$st" == "failed" ]] && break
    fi
    sleep 2
  done

  local result=""
  local rf="$agent_dir/results/${task_id}.result.json"
  local lf="$agent_dir/.live_output"
  [[ -f "$rf" ]] && result=$(cat "$rf")
  [[ -z "$result" && -f "$lf" ]] && result=$(cat "$lf")
  echo "$result" > "$output_file"

  cmd_stop "$agent_name" 2>/dev/null || true
  rm -rf "$agent_dir" 2>/dev/null || true

  echo "$result" | grep -q "VERDICT: PASS"
}

_build_worker_summary() {
  local goal="$1" state_file="$2" feedback="$3" tmpl_body="$4"
  local cycle
  cycle=$(jq -r '.current_cycle // 0' "$state_file" 2>/dev/null)

  echo "$tmpl_body"
  echo ""
  echo "---"
  echo ""
  echo "## Your Task"
  echo ""
  echo "Goal: ${goal}"

  if [[ "$cycle" -gt 0 ]]; then
    echo ""
    echo "Previous attempts (${cycle} cycles so far):"

    if [[ "$cycle" -le 3 ]]; then
      # Show all attempts in detail
      jq -r '.attempts[]? | "- Cycle \(.cycle): \(.status): \(.failed_reason[:200] // "unknown")"' "$state_file" 2>/dev/null
    else
      # Summarize old attempts, detail only last 3
      local old_count=$((cycle - 3))
      local old_reasons
      old_reasons=$(jq -r "[.attempts[:${old_count}][]? | .failed_reason[:80] // \"unknown\"] | join(\"; \")" "$state_file" 2>/dev/null)
      echo "Summary of cycles 1-${old_count}: ${old_reasons}"
      echo ""
      # Detail last 3
      jq -r ".attempts[-3:][]? | \"- Cycle \(.cycle): \(.status): \(.failed_reason[:200] // \"unknown\")\"" "$state_file" 2>/dev/null
    fi

    echo ""
    echo "Latest validation feedback:"
    echo "$feedback"
    echo ""
    echo "The codebase is in the current directory. All previous changes are present. Address the failing checks."
  fi
}

_goal_loop() {
  local template="$1" goal="$2" max_retries="$3" stimeout="$4" task_content="$5"
  local tmpl_file="$TASKS_DIR/${template}.md"
  local tmpl_body
  tmpl_body=$(_template_body "$tmpl_file")
  local tmpl_runtime
  tmpl_runtime=$(_parse_frontmatter "$tmpl_file" "runtime")
  local use_runtime="$tmpl_runtime"
  [[ "$use_runtime" == "auto" ]] && use_runtime="acp"

  local run_id="${template}-$(date +%s)"
  local run_dir="$RUNS_DIR/$run_id"
  mkdir -p "$run_dir/cycles"

  info "generating validation checks..."
  local project_context
  project_context=$(find . -type f -not -path './.git/*' -not -path './node_modules/*' -not -path './__pycache__/*' -not -path './venv/*' 2>/dev/null | head -50)

  local checks_raw
  checks_raw=$(_generate_checks "$goal" "$project_context")

  local checks_json
  checks_json=$(echo "$checks_raw" | sed 's/^```json//;s/^```//;s/```$//' | jq '.' 2>/dev/null)
  if [[ -z "$checks_json" || "$checks_json" == "null" ]]; then
    die "failed to generate valid checks. Raw output:\n$checks_raw"
  fi

  echo "$checks_json" > "$run_dir/checks.json"

  echo ""
  printf "  ${BOLD}Generated validation checks:${NC}\n"
  local idx=0
  echo "$checks_json" | jq -c '.[]' | while IFS= read -r check; do
    ((idx++)) || true
    local tier desc cmd
    tier=$(echo "$check" | jq -r '.tier')
    desc=$(echo "$check" | jq -r '.description')
    cmd=$(echo "$check" | jq -r '.command // "-"')
    local label
    case "$tier" in
      mechanical) label="MECHANICAL" ;;
      agent)      label="AGENT" ;;
      manual)     label="MANUAL ⚠️" ;;
      *)          label="$tier" ;;
    esac
    if [[ "$cmd" != "-" ]]; then
      printf "    ${idx}. [${label}] ${desc}\n       → ${cmd}\n"
    else
      printf "    ${idx}. [${label}] ${desc}\n"
    fi
  done
  echo ""

  printf "  Accept? [Y/n] "
  read -r approval
  if [[ "$approval" =~ ^[Nn] ]]; then
    info "aborted"
    rm -rf "$run_dir"
    return 1
  fi

  local state_file="$run_dir/state.json"
  jq -n --arg g "$goal" --arg id "$run_id" --arg t "$template" \
    '{run_id:$id, template:$t, goal:$g, status:"running", current_cycle:0, attempts:[]}' \
    > "$state_file"

  cat > "$run_dir/run.md" << RUNMD
# Run: ${run_id}
Goal: ${goal}
Started: $(date '+%Y-%m-%d %H:%M %Z')
Template: ${template}

## Checks
$(echo "$checks_json" | jq -r '.[] | "- [\(.tier | ascii_upcase)] \(.description)"')

---
RUNMD

  info "run ${BOLD}${run_id}${NC} — max ${max_retries} retries, ${stimeout}s per cycle"
  echo ""

  local cycle=0 feedback="" last_failure="" consecutive_same=0
  local run_start=$SECONDS

  while [[ $cycle -lt $max_retries ]]; do
    ((cycle++)) || true
    local cycle_start=$SECONDS
    local pad=$(printf '%03d' $cycle)

    info "── cycle ${BOLD}${cycle}/${max_retries}${NC} ──"

    local worker_instructions
    worker_instructions=$(_build_worker_summary "$goal" "$state_file" "$feedback" "$tmpl_body")

    local worker_name="sage-goal-worker-${cycle}-$(date +%s)"
    local worker_dir="$AGENTS_DIR/$worker_name"

    cmd_create "$worker_name" --runtime acp --agent claude-code 2>/dev/null
    # Point worker at the actual project directory, not its isolated workspace
    local project_dir
    project_dir=$(pwd)
    jq --arg wd "$project_dir" '.workdir = $wd' "$worker_dir/runtime.json" > "${worker_dir}/runtime.json.tmp" \
      && mv "${worker_dir}/runtime.json.tmp" "$worker_dir/runtime.json"
    echo "$worker_instructions" > "$worker_dir/instructions.md"
    cmd_start "$worker_name" 2>/dev/null

    export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
    source "$TOOLS_DIR/common.sh"
    local payload
    payload=$(jq -n --arg t "$(printf '%s\n\nGoal: %s' "$task_content" "$goal")" '{text:$t}')
    local task_id
    task_id=$(send_msg "$worker_name" "$payload")

    info "worker running... (timeout: ${stimeout}s)"
    local deadline=$((SECONDS + stimeout))
    local w_status="$worker_dir/results/${task_id}.status.json"

    while [[ $SECONDS -lt $deadline ]]; do
      if [[ -f "$w_status" ]]; then
        local ws
        ws=$(jq -r '.status' "$w_status" 2>/dev/null)
        [[ "$ws" == "done" || "$ws" == "failed" ]] && break
      fi
      sleep 2
    done

    local worker_output=""
    local w_result="$worker_dir/results/${task_id}.result.json"
    local w_live="$worker_dir/.live_output"
    [[ -f "$w_result" ]] && worker_output=$(cat "$w_result")
    [[ -z "$worker_output" && -f "$w_live" ]] && worker_output=$(cat "$w_live")
    echo "$worker_output" > "$run_dir/cycles/${pad}-worker.md"

    cmd_stop "$worker_name" 2>/dev/null || true
    rm -rf "$worker_dir" 2>/dev/null || true

    # ── Mechanical checks ──
    local mech_results="$run_dir/cycles/${pad}-mechanical.json"
    local mech_pass=true
    local has_mechanical
    has_mechanical=$(jq '[.[] | select(.tier == "mechanical")] | length' "$run_dir/checks.json")

    if [[ "$has_mechanical" -gt 0 ]]; then
      info "mechanical checks..."
      _run_mechanical_checks "$run_dir/checks.json" "$mech_results" || mech_pass=false
    fi

    # ── Agent checks ──
    local has_agent
    has_agent=$(jq '[.[] | select(.tier == "agent")] | length' "$run_dir/checks.json")
    local agent_pass=true
    local validator_output="$run_dir/cycles/${pad}-validator.md"

    if [[ "$mech_pass" == true && "$has_agent" -gt 0 ]]; then
      info "agent validation..."
      _run_validator "$run_dir/checks.json" "$validator_output" "$run_dir" "$stimeout" || agent_pass=false
    elif [[ "$has_agent" -eq 0 ]]; then
      echo "No agent checks." > "$validator_output"
    else
      echo "Skipped — mechanical checks failed." > "$validator_output"
    fi

    # ── Build feedback ──
    local cycle_duration=$(( SECONDS - cycle_start ))
    local cycle_status="FAIL"
    feedback=""

    if [[ "$mech_pass" == true && "$agent_pass" == true ]]; then
      cycle_status="PASS"
    else
      if [[ "$mech_pass" == false && -f "$mech_results" ]]; then
        feedback+="Mechanical check failures:\n"
        feedback+=$(jq -r '.[] | select(.status == "FAIL") | "  ❌ \(.description)\n     Command: \(.command)\n     Exit code: \(.exit_code)\n     Output:\n\(.output[:500])\n"' "$mech_results" 2>/dev/null)
      fi
      if [[ "$agent_pass" == false && -f "$validator_output" ]]; then
        feedback+="\nAgent check failures:\n"
        local fail_lines
        fail_lines=$(grep -B1 -A3 "STATUS: FAIL" "$validator_output" 2>/dev/null || echo "  (no details)")
        feedback+="$fail_lines"
      fi
    fi

    # ── Append to run.md ──
    cat >> "$run_dir/run.md" << CYCLEMD

## Cycle ${cycle} — $(date '+%H:%M')
**Duration:** ${cycle_duration}s
**Checks:**
CYCLEMD
    if [[ -f "$mech_results" ]]; then
      jq -r '.[] | (if .status == "PASS" then "  ✅ " else "  ❌ " end) + .description' "$mech_results" >> "$run_dir/run.md"
    fi
    if [[ "$has_agent" -gt 0 && -f "$validator_output" ]]; then
      grep -E "^(CHECK|STATUS):" "$validator_output" 2>/dev/null | paste - - | \
        sed 's/CHECK: \(.*\)\tSTATUS: PASS/  ✅ \1/;s/CHECK: \(.*\)\tSTATUS: FAIL/  ❌ \1/' \
        >> "$run_dir/run.md" 2>/dev/null || true
    fi
    echo "**Result:** ${cycle_status}" >> "$run_dir/run.md"

    # ── Update state ──
    local attempt_json
    attempt_json=$(jq -n --argjson c "$cycle" --arg s "$cycle_status" \
      --arg r "$(echo -e "${feedback:0:500}")" --argjson d "$cycle_duration" \
      '{cycle:$c, status:$s, failed_reason:$r, duration_s:$d}')
    jq --argjson a "$attempt_json" --argjson c "$cycle" \
      '.current_cycle = $c | .attempts += [$a]' "$state_file" > "${state_file}.tmp" \
      && mv "${state_file}.tmp" "$state_file"

    # ── Trace ──
    _trace "{\"ts\":$(date +%s),\"type\":\"goal_cycle\",\"run\":\"$run_id\",\"cycle\":$cycle,\"status\":\"$cycle_status\"}"

    # ── Decision ──
    if [[ "$cycle_status" == "PASS" ]]; then
      local total_duration=$(( SECONDS - run_start ))
      echo "" >> "$run_dir/run.md"
      echo "## Result: PASS ✅ — ${cycle} cycle(s), ${total_duration}s total" >> "$run_dir/run.md"
      jq '.status = "passed"' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
      echo ""
      ok "PASS after ${cycle} cycle(s), ${total_duration}s"
      info "run log: sage runs ${run_id}"
      return 0
    fi

    # Circle detection
    local current_failure="${feedback:0:200}"
    if [[ "$current_failure" == "$last_failure" && -n "$current_failure" ]]; then
      ((consecutive_same++)) || true
    else
      consecutive_same=1
      last_failure="$current_failure"
    fi

    if [[ $consecutive_same -ge 3 ]]; then
      local total_duration=$(( SECONDS - run_start ))
      echo "" >> "$run_dir/run.md"
      echo "## Result: ESCALATED — same failure 3x (${total_duration}s)" >> "$run_dir/run.md"
      jq '.status = "escalated"' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
      echo ""
      warn "same failure 3 times — escalating"
      printf "  ${BOLD}Last failure:${NC}\n"
      echo -e "$feedback" | head -20
      echo ""
      info "run log: sage runs ${run_id}"
      return 1
    fi

    warn "cycle ${cycle} failed — retrying"
    echo ""
  done

  local total_duration=$(( SECONDS - run_start ))
  echo "" >> "$run_dir/run.md"
  echo "## Result: FAILED — max retries (${max_retries}) exhausted (${total_duration}s)" >> "$run_dir/run.md"
  jq '.status = "failed"' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  echo ""
  warn "max retries (${max_retries}) exhausted after ${total_duration}s"
  info "run log: sage runs ${run_id}"
  return 1
}

cmd_runs() {
  local run_id="" cycle_num="" show_active=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --active|-a) show_active=true; shift ;;
      -c)          cycle_num="$2"; shift 2 ;;
      -*)          die "unknown flag: $1" ;;
      *)           run_id="$1"; shift ;;
    esac
  done

  ensure_init
  mkdir -p "$RUNS_DIR"

  if [[ -z "$run_id" ]]; then
    if [[ "$show_active" == true ]]; then
      printf "  ${BOLD}%-35s %-10s %s${NC}\n" "RUN" "STATUS" "CYCLES"
      for d in "$RUNS_DIR"/*/state.json; do
        [[ -f "$d" ]] || continue
        local st=$(jq -r '.status' "$d")
        [[ "$st" == "running" ]] || continue
        local id=$(jq -r '.run_id' "$d")
        local cy=$(jq -r '.current_cycle' "$d")
        printf "  %-35s %-10s %s\n" "$id" "$st" "$cy"
      done
    else
      printf "  ${BOLD}%-35s %-10s %-8s %s${NC}\n" "RUN" "STATUS" "CYCLES" "GOAL"
      for d in "$RUNS_DIR"/*/state.json; do
        [[ -f "$d" ]] || continue
        local id=$(jq -r '.run_id' "$d")
        local st=$(jq -r '.status' "$d")
        local cy=$(jq -r '.current_cycle' "$d")
        local gl=$(jq -r '.goal[:50]' "$d")
        printf "  %-35s %-10s %-8s %s\n" "$id" "$st" "$cy" "$gl"
      done
    fi
    return 0
  fi

  local rd="$RUNS_DIR/$run_id"
  [[ -d "$rd" ]] || die "run '$run_id' not found"

  if [[ -n "$cycle_num" ]]; then
    local p=$(printf '%03d' "$cycle_num")
    echo "=== Worker output (cycle ${cycle_num}) ==="
    cat "$rd/cycles/${p}-worker.md" 2>/dev/null || echo "(not found)"
    echo ""
    echo "=== Mechanical checks (cycle ${cycle_num}) ==="
    cat "$rd/cycles/${p}-mechanical.json" 2>/dev/null | jq '.' 2>/dev/null || echo "(not found)"
    echo ""
    echo "=== Validator output (cycle ${cycle_num}) ==="
    cat "$rd/cycles/${p}-validator.md" 2>/dev/null || echo "(not found)"
  else
    cat "$rd/run.md"
  fi
}

# ═══════════════════════════════════════════════
# sage task <template> [files...] [flags]
# ═══════════════════════════════════════════════
cmd_task() {
  local template="" message="" runtime_override="" timeout=300 background=false
  local goal="" max_retries=10 session_timeout=600
  local -a files=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --message|-m)         message="$2"; shift 2 ;;
      --runtime|-r)         runtime_override="$2"; shift 2 ;;
      --timeout|-t)         timeout="$2"; shift 2 ;;
      --background|-b)      background=true; shift ;;
      --goal|-g)            goal="$2"; shift 2 ;;
      --retries)            max_retries="$2"; shift 2 ;;
      --session-timeout)    session_timeout="$2"; shift 2 ;;
      --list|-l)            _list_templates "$TASKS_DIR"; return 0 ;;
      -*)                   die "unknown flag: $1" ;;
      *)
        if [[ -z "$template" ]]; then
          template="$1"
        else
          files+=("$1")
        fi
        shift
        ;;
    esac
  done

  [[ -n "$template" ]] || die "usage: sage task <template> [files...] [--message \"...\"] [--runtime <rt>] [--timeout <sec>] [--background]
  sage task --list  — show available templates"

  ensure_init
  local tmpl_file="$TASKS_DIR/${template}.md"
  [[ -f "$tmpl_file" ]] || die "template '$template' not found. Available: $(ls "$TASKS_DIR"/*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ' ')"

  # Parse template metadata
  local tmpl_runtime=$(_parse_frontmatter "$tmpl_file" "runtime")
  local tmpl_input=$(_parse_frontmatter "$tmpl_file" "input")
  local tmpl_desc=$(_parse_frontmatter "$tmpl_file" "description")
  local tmpl_body=$(_template_body "$tmpl_file")

  # Determine runtime
  local use_runtime="${runtime_override:-$tmpl_runtime}"
  [[ "$use_runtime" == "auto" ]] && use_runtime="acp"

  # Validate input
  if [[ "$tmpl_input" == "files" && ${#files[@]} -eq 0 && -z "$message" ]]; then
    die "template '$template' expects files. Usage: sage task $template <file1> [file2...]"
  fi

  # Build task content
  local task_content=""

  # Include file contents
  if [[ ${#files[@]} -gt 0 ]]; then
    task_content+="## Files to process\n\n"
    for f in "${files[@]}"; do
      local filepath="$f"
      [[ -f "$filepath" ]] || die "file not found: $filepath"
      local content
      content=$(cat "$filepath")
      local basename_f=$(basename "$filepath")
      task_content+="### $filepath\n\`\`\`\n${content}\n\`\`\`\n\n"
    done
  fi

  # Include user message
  if [[ -n "$message" ]]; then
    task_content+="## Additional Context\n\n${message}\n"
  fi

  # ── Goal-driven loop mode ──
  if [[ -n "$goal" ]]; then
    mkdir -p "$RUNS_DIR"
    _goal_loop "$template" "$goal" "$max_retries" "$session_timeout" "$(echo -e "$task_content")"
    return $?
  fi

  # Create ephemeral agent
  local agent_name="sage-task-${template}-$(date +%s)"
  local agent_dir="$AGENTS_DIR/$agent_name"

  info "task: ${BOLD}$template${NC} — $tmpl_desc"
  info "agent: $agent_name (runtime=$use_runtime)"

  # Create the agent
  local create_flags="--runtime $use_runtime"
  [[ "$use_runtime" == "acp" ]] && create_flags+=" --agent claude-code"
  cmd_create "$agent_name" $create_flags 2>/dev/null

  # Replace instructions.md with template body + original instructions
  local original_instructions=""
  [[ -f "$agent_dir/instructions.md" ]] && original_instructions=$(cat "$agent_dir/instructions.md")
  cat > "$agent_dir/instructions.md" << INST
${tmpl_body}

---

${original_instructions}
INST

  # Start the agent
  cmd_start "$agent_name" 2>/dev/null

  # Send the task
  export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
  source "$TOOLS_DIR/common.sh"

  local payload
  payload=$(jq -n --arg t "$(echo -e "$task_content")" '{text:$t}')

  local task_id
  task_id=$(send_msg "$agent_name" "$payload")

  # Trace
  _trace "{\"ts\":$(date +%s),\"type\":\"task\",\"template\":\"$template\",\"agent\":\"$agent_name\",\"task_id\":\"$task_id\",\"files\":\"${files[*]}\"}"

  if [[ "$background" == true ]]; then
    ok "task ${BOLD}${task_id}${NC} → $agent_name (background)"
    info "track: sage peek $agent_name | sage tasks $agent_name | sage result $task_id"
    return 0
  fi

  # Wait for completion
  info "executing... (timeout: ${timeout}s)"
  local deadline=$((SECONDS + timeout))
  local result_file="$agent_dir/results/${task_id}.result.json"
  local status_file="$agent_dir/results/${task_id}.status.json"

  while [[ $SECONDS -lt $deadline ]]; do
    if [[ -f "$status_file" ]]; then
      local status=$(jq -r '.status' "$status_file" 2>/dev/null)
      if [[ "$status" == "done" || "$status" == "failed" ]]; then
        echo ""
        if [[ "$status" == "done" ]]; then
          ok "task completed"
        else
          warn "task failed"
        fi

        # Show result
        if [[ -f "$result_file" ]]; then
          echo ""
          cat "$result_file"
        else
          # Check live output
          local live="$agent_dir/.live_output"
          if [[ -f "$live" && -s "$live" ]]; then
            echo ""
            cat "$live"
          else
            info "no structured result — check: sage logs $agent_name"
          fi
        fi

        # Show workspace files
        local ws="$agent_dir/workspace"
        local file_count=$(find "$ws" -maxdepth 2 -type f 2>/dev/null | wc -l)
        if [[ $file_count -gt 0 ]]; then
          echo ""
          printf "  ${BOLD}Files created/modified:${NC}\n"
          find "$ws" -maxdepth 2 -type f -printf "    %P\n" 2>/dev/null
        fi

        # Cleanup ephemeral agent
        cmd_stop "$agent_name" 2>/dev/null || true
        rm -rf "$AGENTS_DIR/$agent_name" 2>/dev/null || true
        echo ""
        return 0
      fi
    fi
    sleep 1
  done

  warn "timeout after ${timeout}s — agent still running"
  info "monitor: sage peek $agent_name"
  info "result:  sage result $task_id"
  info "cleanup: sage stop $agent_name && rm -rf ~/.sage/agents/$agent_name"
  return 1
}

# ═══════════════════════════════════════════════
# sage plan <goal> [flags]
# ═══════════════════════════════════════════════
cmd_plan() {
  local goal="" save_file="" run_file="" resume_file="" auto_approve=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --save)     save_file="$2"; shift 2 ;;
      --run)      run_file="$2"; shift 2 ;;
      --resume)   resume_file="$2"; shift 2 ;;
      --yes|-y)   auto_approve=true; shift ;;
      --list|-l)  _plan_list; return 0 ;;
      -*)         die "unknown flag: $1" ;;
      *)          goal="$goal $1"; shift ;;
    esac
  done

  goal=$(echo "$goal" | sed 's/^ *//')
  ensure_init
  mkdir -p "$PLANS_DIR"

  # Resume from existing plan
  if [[ -n "$resume_file" ]]; then
    [[ -f "$resume_file" ]] || die "plan file not found: $resume_file"
    _plan_execute "$resume_file" "resume"
    return $?
  fi

  # Run from saved plan file
  if [[ -n "$run_file" ]]; then
    [[ -f "$run_file" ]] || die "plan file not found: $run_file"
    _plan_execute "$run_file" "fresh"
    return $?
  fi

  [[ -n "$goal" ]] || die "usage: sage plan <goal> [--save file] [--run file] [--resume file] [--yes]"

  # Build template catalog for the planning prompt
  local template_catalog=""
  for tmpl in "$TASKS_DIR"/*.md; do
    [[ -f "$tmpl" ]] || continue
    local name=$(basename "$tmpl" .md)
    local desc=$(_parse_frontmatter "$tmpl" "description")
    local rt=$(_parse_frontmatter "$tmpl" "runtime")
    template_catalog+="  - ${name}: ${desc} (runtime: ${rt})\n"
  done

  info "planning: ${BOLD}$goal${NC}"

  # Create planning agent
  local plan_agent="sage-planner-$(date +%s)"
  cmd_create "$plan_agent" --runtime acp --agent claude-code 2>/dev/null

  # Write planning instructions
  cat > "$AGENTS_DIR/$plan_agent/instructions.md" << PLANINST
# Task Planner

You are a task planner for the sage orchestration system. You break down goals into independent, parallelizable tasks.

## Available Task Templates

$(echo -e "$template_catalog")

## Your Job

Given a goal, produce a JSON plan. Each task uses one of the templates above.

Think carefully about:
- What order tasks need to happen in
- Which tasks can run in parallel (no dependencies between them)
- What the minimum set of tasks is to achieve the goal
- What context each task needs from previous tasks

## Output Format

Return ONLY valid JSON, no markdown fences, no explanation:

{
  "goal": "the original goal",
  "tasks": [
    {
      "id": 1,
      "template": "spec",
      "description": "What specifically this task should do",
      "depends": [],
      "files": []
    },
    {
      "id": 2,
      "template": "implement",
      "description": "Implement the token endpoint per the spec",
      "depends": [1],
      "files": ["src/auth/"]
    }
  ]
}

Rules:
- Use real template names from the list above
- Task IDs are sequential integers starting at 1
- depends is an array of task IDs that must complete first
- files is an array of file paths relevant to this task (can be empty)
- Keep descriptions specific and actionable, not vague
- Prefer fewer tasks over many tiny ones
- Don't create circular dependencies
PLANINST

  cmd_start "$plan_agent" 2>/dev/null

  # Send the goal
  export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
  source "$TOOLS_DIR/common.sh"

  local payload
  payload=$(jq -n --arg t "Plan the following goal. Return ONLY JSON.\n\nGoal: $goal" '{text:$t}')
  local task_id
  task_id=$(send_msg "$plan_agent" "$payload")

  # Wait for the plan
  info "thinking..."
  local deadline=$((SECONDS + 120))
  local plan_json=""

  while [[ $SECONDS -lt $deadline ]]; do
    local status_file="$AGENTS_DIR/$plan_agent/results/${task_id}.status.json"
    if [[ -f "$status_file" ]]; then
      local status=$(jq -r '.status' "$status_file" 2>/dev/null)
      if [[ "$status" == "done" ]]; then
        # Get the result
        local result_file="$AGENTS_DIR/$plan_agent/results/${task_id}.result.json"
        local live_output="$AGENTS_DIR/$plan_agent/.live_output"

        if [[ -f "$result_file" ]]; then
          plan_json=$(cat "$result_file")
        elif [[ -f "$live_output" ]]; then
          plan_json=$(cat "$live_output")
        fi
        break
      fi
    fi
    sleep 1
  done

  # Stop the planning agent
  cmd_stop "$plan_agent" 2>/dev/null || true

  [[ -n "$plan_json" ]] || die "planning timed out — no plan generated"

  # Extract JSON from the response
  local extracted=""
  local live_output="$AGENTS_DIR/$plan_agent/.live_output"
  local raw_text="$plan_json"
  [[ -f "$live_output" ]] && raw_text=$(cat "$live_output")

  # Use python3 for robust JSON extraction and normalization
  local raw_file=$(mktemp)
  echo "$raw_text" > "$raw_file"

  extracted=$(python3 -c "
import json, re, sys

with open('$raw_file') as f:
    raw = f.read()

# Strip markdown code fences
raw = re.sub(r'\`\`\`json\s*', '', raw)
raw = re.sub(r'\`\`\`\s*', '', raw)

# Find the first JSON object
depth = 0
start = -1
for i, c in enumerate(raw):
    if c == '{':
        if depth == 0: start = i
        depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0 and start >= 0:
            try:
                obj = json.loads(raw[start:i+1])
                print(json.dumps(obj))
                sys.exit(0)
            except json.JSONDecodeError:
                start = -1
                continue

sys.exit(1)
" 2>/dev/null) || true
  rm -f "$raw_file"

  if [[ -z "$extracted" ]] || ! echo "$extracted" | jq . >/dev/null 2>&1; then
    die "could not parse plan JSON. Check: sage logs $plan_agent"
  fi

  plan_json="$extracted"

  # Normalize — agents use wildly different field names
  # Map: steps→tasks, dependencies→depends, actions→description, assign templates
  local templates_list
  templates_list=$(ls "$TASKS_DIR"/*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ',' | sed 's/,$//')

  local norm_input=$(mktemp)
  echo "$plan_json" > "$norm_input"

  plan_json=$(python3 -c "
import json, re

with open('$norm_input') as f:
    plan = json.load(f)
templates = '$templates_list'.split(',')

# Normalize tasks array
tasks = plan.get('tasks', plan.get('steps', []))
normalized = []
for t in tasks:
    desc = t.get('description', t.get('title', ''))
    # If actions list exists, fold into description
    actions = t.get('actions', [])
    if actions and isinstance(actions, list):
        desc += '. ' + '; '.join(str(a) for a in actions)

    # Assign template based on description keywords
    template = t.get('template', None)
    if not template or template not in templates:
        desc_lower = desc.lower()
        if any(w in desc_lower for w in ['test', 'verify', 'check', 'assert']):
            template = 'test'
        elif any(w in desc_lower for w in ['spec', 'design', 'plan', 'define', 'determine', 'choose', 'select']):
            template = 'spec'
        elif any(w in desc_lower for w in ['review', 'audit', 'inspect']):
            template = 'review'
        elif any(w in desc_lower for w in ['refactor', 'clean', 'restructure']):
            template = 'refactor'
        elif any(w in desc_lower for w in ['document', 'readme', 'docs', 'docstring']):
            template = 'document'
        elif any(w in desc_lower for w in ['debug', 'fix', 'diagnose', 'reproduce']):
            template = 'debug'
        else:
            template = 'implement'

    normalized.append({
        'id': t.get('id', len(normalized) + 1),
        'template': template,
        'description': desc,
        'depends': t.get('depends', t.get('dependencies', [])),
        'files': t.get('files', [])
    })

plan['tasks'] = normalized
# Remove non-standard fields
for key in list(plan.keys()):
    if key not in ('goal', 'tasks', 'plan_id', 'status'):
        del plan[key]

print(json.dumps(plan))
" 2>/dev/null) || die "failed to normalize plan"
  rm -f "$norm_input"

  # Save the plan
  local plan_id="plan-$(date +%s)"
  local plan_file="$PLANS_DIR/${plan_id}.json"

  echo "$plan_json" | jq --arg id "$plan_id" --arg status "pending" \
    '. + {plan_id: $id, status: $status}' > "$plan_file"

  # Display the plan
  _plan_display "$plan_file"

  # Save to custom file if requested
  if [[ -n "$save_file" ]]; then
    cp "$plan_file" "$save_file"
    ok "plan saved to $save_file"
  fi

  # Approval
  if [[ "$auto_approve" == true ]]; then
    _plan_execute "$plan_file" "fresh"
    local exec_rc=$?
    rm -rf "$AGENTS_DIR/$plan_agent" 2>/dev/null || true
    return $exec_rc
  fi

  echo ""
  printf "  ${BOLD}[a]${NC}pprove  ${BOLD}[e]${NC}dit  ${BOLD}[r]${NC}eject  "
  read -r choice

  case "$choice" in
    a|approve)
      _plan_execute "$plan_file" "fresh"
      ;;
    e|edit)
      _plan_edit "$plan_file"
      _plan_display "$plan_file"
      echo ""
      printf "  ${BOLD}[a]${NC}pprove  ${BOLD}[r]${NC}eject  "
      read -r choice2
      if [[ "$choice2" == "a" || "$choice2" == "approve" ]]; then
        _plan_execute "$plan_file" "fresh"
      else
        info "plan rejected"
      fi
      ;;
    r|reject)
      info "plan rejected"
      ;;
    *)
      warn "unknown choice. Plan saved at: $plan_file"
      info "run later: sage plan --run $plan_file"
      ;;
  esac

  # Cleanup planning agent
  rm -rf "$AGENTS_DIR/$plan_agent" 2>/dev/null || true
}

# Display a plan
_plan_display() {
  local plan_file="$1"
  local goal=$(jq -r '.goal' "$plan_file")
  local task_count=$(jq '.tasks | length' "$plan_file")

  echo ""
  printf "  ${BOLD}📋 Plan: %s${NC}\n\n" "$goal"

  # Display tasks
  jq -r '.tasks[] | "  #\(.id) [\(.template)] \(.description)\(if (.depends | length) > 0 then " (depends: \(.depends | map("#\(.)") | join(", ")))" else "" end)"' "$plan_file" | while IFS= read -r line; do
    printf "%s\n" "$line"
  done

  # Compute and display waves
  echo ""
  printf "  ${BOLD}Waves:${NC}\n"
  _compute_waves "$plan_file" | while IFS= read -r wave_line; do
    printf "  %s\n" "$wave_line"
  done
}

# Compute execution waves from dependencies
_compute_waves() {
  local plan_file="$1"

  python3 -c "
import json, sys

with open('$plan_file') as f:
    plan = json.load(f)

tasks = plan.get('tasks', [])
if not tasks:
    sys.exit(0)

# Build adjacency and compute waves with proper topological ordering
task_map = {t['id']: t for t in tasks}
waves = {}
max_iter = len(tasks) + 1  # cycle detection

def get_wave(tid, visited=None):
    if tid in waves:
        return waves[tid]
    if visited is None:
        visited = set()
    if tid in visited:
        return 1  # cycle detected — break it
    visited.add(tid)
    task = task_map.get(tid)
    if not task:
        return 1
    deps = task.get('depends', [])
    if not deps:
        waves[tid] = 1
        return 1
    max_dep = max(get_wave(d, visited.copy()) for d in deps)
    waves[tid] = max_dep + 1
    return waves[tid]

for t in tasks:
    get_wave(t['id'])

max_wave = max(waves.values()) if waves else 0
for w in range(1, max_wave + 1):
    ids = [t['id'] for t in tasks if waves.get(t['id']) == w]
    if not ids:
        continue
    id_str = ', '.join(f'#{i}' for i in ids)
    parallel = ' (parallel)' if len(ids) > 1 else ''
    print(f'  Wave {w}: {id_str}{parallel}')
" 2>/dev/null || echo "  (could not compute waves)"
}

# Interactive plan editor
_plan_edit() {
  local plan_file="$1"

  echo ""
  printf "  ${BOLD}Edit commands:${NC}\n"
  printf "  ${DIM}drop <id>                     — remove a task${NC}\n"
  printf "  ${DIM}add <template> \"desc\" [--depends N,M] — add a task${NC}\n"
  printf "  ${DIM}edit <id> \"new description\"   — change task description${NC}\n"
  printf "  ${DIM}depends <id> <dep1,dep2,...>   — set dependencies${NC}\n"
  printf "  ${DIM}done                          — finish editing${NC}\n"
  echo ""

  while true; do
    printf "  ${CYAN}edit>${NC} "
    read -r cmd args

    case "$cmd" in
      drop)
        local drop_id=$(echo "$args" | tr -d ' ')
        if jq -e ".tasks[] | select(.id == ($drop_id))" "$plan_file" >/dev/null 2>&1; then
          local tmp=$(mktemp)
          jq "(.tasks) |= map(select(.id != ($drop_id))) | (.tasks) |= map(if .depends then .depends |= map(select(. != ($drop_id))) else . end)" "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
          ok "dropped task #$drop_id"
        else
          warn "task #$drop_id not found"
        fi
        ;;

      add)
        local tmpl="" desc="" deps=""
        # Parse: add <template> "description" [--depends N,M]
        tmpl=$(echo "$args" | awk '{print $1}')
        desc=$(echo "$args" | grep -oP '"[^"]*"' | tr -d '"' | head -1)
        deps=$(echo "$args" | grep -oP '\-\-depends\s+\K[0-9,]+' || echo "")

        if [[ -z "$tmpl" || -z "$desc" ]]; then
          warn "usage: add <template> \"description\" [--depends N,M]"
          continue
        fi

        # Check template exists
        if [[ ! -f "$TASKS_DIR/${tmpl}.md" ]]; then
          warn "template '$tmpl' not found"
          continue
        fi

        # Get next ID
        local next_id=$(jq '[.tasks[].id] | max + 1' "$plan_file")
        local deps_array="[]"
        if [[ -n "$deps" ]]; then
          deps_array=$(echo "$deps" | tr ',' '\n' | jq -R 'tonumber' | jq -s '.')
        fi

        local tmp=$(mktemp)
        jq --arg tmpl "$tmpl" --arg desc "$desc" --argjson id "$next_id" --argjson deps "$deps_array" \
          '.tasks += [{"id": $id, "template": $tmpl, "description": $desc, "depends": $deps, "files": []}]' \
          "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
        ok "added task #$next_id [$tmpl] $desc"
        ;;

      edit)
        local edit_id=$(echo "$args" | awk '{print $1}')
        local new_desc=$(echo "$args" | grep -oP '"[^"]*"' | tr -d '"' | head -1)
        if [[ -z "$edit_id" || -z "$new_desc" ]]; then
          warn "usage: edit <id> \"new description\""
          continue
        fi
        local tmp=$(mktemp)
        jq --argjson id "$edit_id" --arg desc "$new_desc" \
          '(.tasks[] | select(.id == $id)).description = $desc' \
          "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
        ok "updated task #$edit_id"
        ;;

      depends)
        local dep_id=$(echo "$args" | awk '{print $1}')
        local dep_list=$(echo "$args" | awk '{print $2}')
        if [[ -z "$dep_id" || -z "$dep_list" ]]; then
          warn "usage: depends <id> <dep1,dep2,...>"
          continue
        fi
        local deps_array=$(echo "$dep_list" | tr ',' '\n' | jq -R 'tonumber' | jq -s '.')
        local tmp=$(mktemp)
        jq --argjson id "$dep_id" --argjson deps "$deps_array" \
          '(.tasks[] | select(.id == $id)).depends = $deps' \
          "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
        ok "set dependencies for #$dep_id"
        ;;

      done|d|approve|a)
        break
        ;;

      show|s)
        _plan_display "$plan_file"
        ;;

      *)
        warn "unknown command: $cmd (try: drop, add, edit, depends, show, done)"
        ;;
    esac
  done
}

# Execute a plan
_plan_execute() {
  local plan_file="$1" mode="$2"
  local goal=$(jq -r '.goal' "$plan_file")
  local task_count=$(jq '.tasks | length' "$plan_file")

  echo ""
  printf "  ${BOLD}⚡ Executing plan: %s${NC}\n" "$goal"
  printf "  ${DIM}%d tasks${NC}\n\n" "$task_count"

  # Update plan status
  local tmp=$(mktemp)
  jq '.status = "running"' "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"

  # Source tools for send_msg
  export SAGE_AGENT_NAME="${SAGE_AGENT_NAME:-cli}"
  source "$TOOLS_DIR/common.sh"

  # Compute wave assignments using python3 (handles arbitrary task ordering + cycles)
  local wave_json
  wave_json=$(python3 -c "
import json
with open('$plan_file') as f:
    plan = json.load(f)
tasks = plan.get('tasks', [])
task_map = {t['id']: t for t in tasks}
waves = {}

def get_wave(tid, visited=None):
    if tid in waves:
        return waves[tid]
    if visited is None:
        visited = set()
    if tid in visited:
        return 1
    visited.add(tid)
    task = task_map.get(tid)
    if not task:
        return 1
    deps = task.get('depends', [])
    if not deps:
        waves[tid] = 1
        return 1
    max_dep = max(get_wave(d, visited.copy()) for d in deps)
    waves[tid] = max_dep + 1
    return waves[tid]

for t in tasks:
    get_wave(t['id'])
print(json.dumps({str(k): v for k, v in waves.items()}))
" 2>/dev/null) || die "failed to compute waves"

  local max_wave=$(echo "$wave_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(max(d.values()) if d else 0)")
  local prev_results="{}"

  for wave_num in $(seq 1 "$max_wave"); do
    # Get tasks in this wave
    local wave_task_ids
    wave_task_ids=$(echo "$wave_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k, v in d.items():
    if v == $wave_num:
        print(k)
")

    [[ -n "$wave_task_ids" ]] || continue

    local wave_count=$(echo "$wave_task_ids" | wc -l)
    printf "  ${BOLD}Wave %d${NC} (%d task%s)\n" "$wave_num" "$wave_count" "$([ "$wave_count" -gt 1 ] && echo 's' || echo '')"

    # Update plan current_wave
    tmp=$(mktemp)
    jq --argjson w "$wave_num" '.current_wave = $w' "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"

    # Track agents for this wave
    local -a wave_agents=()
    local -a wave_task_tracking=()

    # Phase 1: Create and start all agents for this wave
    local wave_data_dir=$(mktemp -d)

    while IFS= read -r tid; do
      [[ -n "$tid" ]] || continue

      # Skip if already done (resume mode); reset stale "running" to pending
      local task_status=$(jq -r ".tasks[] | select(.id == $tid) | .status // \"pending\"" "$plan_file")
      if [[ "$mode" == "resume" && "$task_status" == "done" ]]; then
        printf "    ${DIM}#%s — skipped (already done)${NC}\n" "$tid"
        continue
      fi
      if [[ "$mode" == "resume" && "$task_status" == "running" ]]; then
        # Stale from a crash — reset to pending
        tmp=$(mktemp)
        jq --argjson tid "$tid" '(.tasks[] | select(.id == $tid)).status = "pending"' "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
        printf "    ${YELLOW}↻${NC} #%s — reset from stale 'running' to pending\n" "$tid"
      fi

      local task_template=$(jq -r ".tasks[] | select(.id == $tid) | .template" "$plan_file")
      local task_desc=$(jq -r ".tasks[] | select(.id == $tid) | .description" "$plan_file")
      local task_deps=$(jq -r ".tasks[] | select(.id == $tid) | .depends // [] | join(\",\")" "$plan_file")
      local task_files=$(jq -r ".tasks[] | select(.id == $tid) | .files // [] | join(\" \")" "$plan_file")

      # Build context from dependencies
      local dep_context=""
      if [[ -n "$task_deps" ]]; then
        for dep_id in $(echo "$task_deps" | tr ',' ' '); do
          local dep_result=$(echo "$prev_results" | jq -r ".\"$dep_id\" // \"\"")
          if [[ -n "$dep_result" && "$dep_result" != "" ]]; then
            dep_context+="\n## Result from task #$dep_id\n$dep_result\n"
          fi
        done
      fi

      # Determine runtime from template
      local tmpl_file="$TASKS_DIR/${task_template}.md"
      local tmpl_runtime="acp"
      [[ -f "$tmpl_file" ]] && tmpl_runtime=$(_parse_frontmatter "$tmpl_file" "runtime")
      [[ "$tmpl_runtime" == "auto" ]] && tmpl_runtime="acp"

      # Create ephemeral agent
      local agent_name="sage-plan-${tid}-$(date +%s)"
      local create_flags="--runtime $tmpl_runtime"
      [[ "$tmpl_runtime" == "acp" ]] && create_flags+=" --agent claude-code"
      
      if ! cmd_create "$agent_name" $create_flags 2>/dev/null; then
        warn "failed to create agent for task #$tid — skipping"
        continue
      fi

      # Inject template as instructions
      if [[ -f "$tmpl_file" ]]; then
        local tmpl_body=$(_template_body "$tmpl_file")
        local original_instr=""
        [[ -f "$AGENTS_DIR/$agent_name/instructions.md" ]] && original_instr=$(cat "$AGENTS_DIR/$agent_name/instructions.md")
        cat > "$AGENTS_DIR/$agent_name/instructions.md" << INST
${tmpl_body}

---

${original_instr}
INST
      fi

      # Start agent
      if ! cmd_start "$agent_name" 2>/dev/null; then
        warn "failed to start agent $agent_name — skipping task #$tid"
        rm -rf "$AGENTS_DIR/$agent_name" 2>/dev/null
        continue
      fi

      # Store data for phase 2 as JSON files (avoids delimiter issues)
      jq -n \
        --arg tid "$tid" \
        --arg agent "$agent_name" \
        --arg template "$task_template" \
        --arg desc "$task_desc" \
        --arg deps "$dep_context" \
        --arg files "$task_files" \
        '{tid:$tid, agent:$agent, template:$template, desc:$desc, deps:$deps, files:$files}' \
        > "$wave_data_dir/${tid}.json"

      sleep 1  # stagger starts
    done <<< "$wave_task_ids"

    # Phase 2: Wait for all ACP runtimes to initialize
    local started_count=$(ls "$wave_data_dir"/*.json 2>/dev/null | wc -l)
    if [[ $started_count -gt 0 ]]; then
      info "agents started, waiting for runtime initialization..."
      sleep 4
    fi

    # Phase 3: Send messages to all agents
    for data_file in "$wave_data_dir"/*.json; do
      [[ -f "$data_file" ]] || continue

      local tid=$(jq -r '.tid' "$data_file")
      local agent_name=$(jq -r '.agent' "$data_file")
      local task_template=$(jq -r '.template' "$data_file")
      local task_desc=$(jq -r '.desc' "$data_file")
      local dep_context=$(jq -r '.deps' "$data_file")
      local task_files=$(jq -r '.files' "$data_file")

      # Build message
      local msg_text="$task_desc"
      [[ -n "$dep_context" ]] && msg_text+="\n$(echo -e "$dep_context")"
      if [[ -n "$task_files" ]]; then
        msg_text+="\n\n## Relevant files\n"
        for f in $task_files; do
          [[ -f "$f" ]] && msg_text+="\n### $f\n\`\`\`\n$(cat "$f")\n\`\`\`\n"
        done
      fi

      local payload
      payload=$(jq -n --arg t "$(echo -e "$msg_text")" '{text:$t}')
      local sent_task_id
      sent_task_id=$(send_msg "$agent_name" "$payload")

      printf "    ${CYAN}#%s${NC} [%s] → %s (%s)\n" "$tid" "$task_template" "$agent_name" "$sent_task_id"

      wave_agents+=("$agent_name")
      wave_task_tracking+=("$tid:$agent_name:$sent_task_id")

      # Update plan state
      tmp=$(mktemp)
      jq --argjson tid "$tid" --arg agent "$agent_name" --arg st "$sent_task_id" \
        '(.tasks[] | select(.id == $tid)) |= . + {status: "running", agent: $agent, sage_task_id: $st}' \
        "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"

    done  # end Phase 3 for loop

    # Wait for all agents in this wave
    if [[ ${#wave_agents[@]} -gt 0 ]]; then
      printf "    ${DIM}waiting for wave %d...${NC}\n" "$wave_num"

      local completed=0
      local total=${#wave_task_tracking[@]}
      local wave_timeout=$((600 * total))
      local wave_deadline=$((SECONDS + wave_timeout))
      local -A wave_done

      while [[ $completed -lt $total && $SECONDS -lt $wave_deadline ]]; do
        for tracking in "${wave_task_tracking[@]}"; do
          local t_id=$(echo "$tracking" | cut -d: -f1)
          local a_name=$(echo "$tracking" | cut -d: -f2)
          local s_tid=$(echo "$tracking" | cut -d: -f3)

          [[ -n "${wave_done[$t_id]:-}" ]] && continue

          local sf="$AGENTS_DIR/$a_name/results/${s_tid}.status.json"
          if [[ -f "$sf" ]]; then
            local st=$(jq -r '.status' "$sf" 2>/dev/null)
            if [[ "$st" == "done" || "$st" == "failed" ]]; then
              wave_done[$t_id]=1
              ((completed++)) || true

              # Collect result
              local rf="$AGENTS_DIR/$a_name/results/${s_tid}.result.json"
              local lo="$AGENTS_DIR/$a_name/.live_output"
              local result_text=""
              if [[ -f "$rf" ]]; then
                result_text=$(cat "$rf" | head -c 2000)
              elif [[ -f "$lo" ]]; then
                result_text=$(cat "$lo" | head -c 2000)
              fi

              # Store result for downstream tasks
              prev_results=$(echo "$prev_results" | jq --arg k "$t_id" --arg v "$result_text" '. + {($k): $v}')

              # Update plan
              tmp=$(mktemp)
              jq --argjson tid "$t_id" --arg st "$st" '.tasks[] |= (if .id == $tid then .status = $st else . end)' \
                "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"

              if [[ "$st" == "done" ]]; then
                printf "    ${GREEN}✓${NC} #%s completed (%d/%d)\n" "$t_id" "$completed" "$total"
              else
                printf "    ${RED}✗${NC} #%s failed (%d/%d)\n" "$t_id" "$completed" "$total"
              fi

              # Stop the ephemeral agent
              cmd_stop "$a_name" 2>/dev/null || true
              rm -rf "$AGENTS_DIR/$a_name" 2>/dev/null || true
            fi
          fi
        done
        sleep 2
      done

      if [[ $completed -lt $total ]]; then
        echo ""
        warn "wave $wave_num: $((total - completed)) task(s) timed out"

        for tracking in "${wave_task_tracking[@]}"; do
          local t_id=$(echo "$tracking" | cut -d: -f1)
          local a_name=$(echo "$tracking" | cut -d: -f2)
          [[ -n "${wave_done[$t_id]:-}" ]] && continue
          printf "    ${RED}✗${NC} #%s timed out (agent: %s)\n" "$t_id" "$a_name"

          # Update plan
          tmp=$(mktemp)
          jq --argjson tid "$t_id" '.tasks[] |= (if .id == $tid then .status = "failed" else . end)' \
            "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
        done

        echo ""
        printf "  ${BOLD}[r]${NC}etry  ${BOLD}[s]${NC}kip  ${BOLD}[a]${NC}bort  "
        read -r fail_choice
        case "$fail_choice" in
          r|retry)
            info "retrying wave $wave_num..."
            # Decrement wave to re-run
            ((wave_num--))
            continue
            ;;
          s|skip)
            warn "skipping failed tasks — downstream tasks may fail"
            ;;
          a|abort|*)
            tmp=$(mktemp)
            jq '.status = "aborted"' "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"
            die "plan aborted"
            ;;
        esac
      fi
    fi

    # Cleanup wave temp data
    rm -rf "$wave_data_dir" 2>/dev/null

    echo ""
  done

  # Mark plan as completed
  tmp=$(mktemp)
  jq '.status = "completed"' "$plan_file" > "$tmp" && mv "$tmp" "$plan_file"

  echo ""
  ok "plan completed! ($task_count tasks across $max_wave waves)"
  info "plan file: $plan_file"
}

# List saved plans
_plan_list() {
  ensure_init
  mkdir -p "$PLANS_DIR"

  printf "\n${BOLD}  📋 Plans${NC}\n\n"
  printf "  ${DIM}%-30s %-12s %-6s %s${NC}\n" "FILE" "STATUS" "TASKS" "GOAL"

  local found=0
  for pf in "$PLANS_DIR"/*.json; do
    [[ -f "$pf" ]] || continue
    ((found++)) || true
    local status=$(jq -r '.status // "unknown"' "$pf")
    local goal=$(jq -r '.goal // "?"' "$pf" | head -c 50)
    local tasks=$(jq '.tasks | length' "$pf")
    local fname=$(basename "$pf")

    local status_color="$NC"
    case "$status" in
      completed) status_color="$GREEN" ;;
      running)   status_color="$YELLOW" ;;
      failed|aborted) status_color="$RED" ;;
    esac

    printf "  %-30s ${status_color}%-12s${NC} %-6s %s\n" "$fname" "$status" "$tasks" "$goal"
  done

  [[ $found -eq 0 ]] && printf "  ${DIM}no plans${NC}\n"
  echo ""
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
    create <name> [flags]       Create agent (--runtime bash|cline|claude-code|acp, --agent <a>, --model <m>)
    start [name|--all]          Start agent(s) in tmux
    stop [name|--all]           Stop agent(s)
    restart [name|--all]        Restart agent(s)
    status                      Show all agents
    ls                          List agent names
    rm <name>                   Remove agent
    clean                       Clean up stale files

  MESSAGING
    send <to> <message|@file> [--force] Fire-and-forget (--force cancels running task)
    call <to> <message|@file> [s]  Send and wait for response (default: 60s)
    tasks [name]                List tasks with status
    result <task-id>            Get task result
    wait <name> [--timeout N]   Wait for agent to finish (long-running tasks)
    peek <name> [--lines N]     See what agent is doing (tmux pane + workspace)
    steer <name> <msg> [--restart] Course-correct a running agent
    inbox [--json] [--clear]    View/clear messages sent to you (.cli)

  TASK TEMPLATES
    task --list                 Show available templates
    task <template> [files...]  Execute a task template
      [--message "..."]         Additional context
      [--runtime <rt>]          Override template runtime
      [--timeout <sec>]         Timeout (default: 300s)
      [--background]            Run async, return task ID

  PLAN ORCHESTRATOR
    plan <goal>                 Decompose goal into task waves
      [--save <file>]           Save plan to file
      [--yes]                   Auto-approve (skip interactive)
    plan --run <file>           Execute a saved plan
    plan --resume <file>        Resume from failure point
    plan --list                 Show saved plans

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
    acp           Agent Client Protocol — universal agent bridge
                  Use --agent to specify: cline, claude-code, goose, kiro, gemini, or any ACP agent
                  Supports live steering: follow-up messages go into the same session

  LONG-RUNNING TASKS
    sage send orch 'Build the entire app'      # fire & forget (non-blocking)
    sage tasks orch                      # check status
    sage peek orch                       # see what it's doing
    sage send orch "Use React" --force   # cancel current task, switch direction
    sage steer orch "Use REST not GraphQL"  # course-correct (next task)
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
  send)    shift; cmd_send "$@" ;;
  call)    shift; cmd_call "$@" ;;
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
  merge)   cmd_merge "${2:-}" ;;
  clean)   cmd_clean ;;
  tool)    shift; cmd_tool "$@" ;;
  task)    shift; cmd_task "$@" ;;
  runs)    shift; cmd_runs "$@" ;;
  plan)    shift; cmd_plan "$@" ;;
  help|-h|--help|"") cmd_help ;;
  *)       die "unknown command: $1. Run: sage help" ;;
esac
