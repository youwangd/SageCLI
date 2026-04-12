#!/bin/bash
# sage — Simple Agent Engine
# Unix-native agent dispatching and management
# Dependencies: bash, jq, tmux

set -euo pipefail

SAGE_VERSION="1.3.0"
SAGE_HOME="${SAGE_HOME:-$HOME/.sage}"
AGENTS_DIR="$SAGE_HOME/agents"
TOOLS_DIR="$SAGE_HOME/tools"
RUNTIMES_DIR="$SAGE_HOME/runtimes"
LOGS_DIR="$SAGE_HOME/logs"
SKILLS_DIR="$SAGE_HOME/skills"
REGISTRIES_DIR="$SAGE_HOME/registries"
CONTEXT_DIR="$SAGE_HOME/context"
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
_config_get() { [[ -f "$SAGE_HOME/config.json" ]] && jq -r --arg k "$1" '.[$k] // empty' "$SAGE_HOME/config.json" 2>/dev/null || true; }
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

  mkdir -p "$AGENTS_DIR" "$TOOLS_DIR" "$RUNTIMES_DIR" "$LOGS_DIR" "$AGENTS_DIR/.cli/replies" "$SAGE_HOME/tasks" "$SAGE_HOME/plans" "$SKILLS_DIR" "$REGISTRIES_DIR" "$CONTEXT_DIR"
  [[ -f "$SAGE_HOME/config.json" ]] || echo '{}' > "$SAGE_HOME/config.json"

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
  _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$_acp_rpc_id,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{\"fs\":{\"readTextFile\":true,\"writeTextFile\":true},\"terminal\":true},\"clientInfo\":{\"name\":\"sage\",\"version\":\"$SAGE_VERSION\"}}}"
  ((_acp_rpc_id++))
  local r=$(_acp_read 15)
  local aname=$(echo "$r" | jq -r '.result.agentInfo.name // "unknown"' 2>/dev/null)
  local aver=$(echo "$r" | jq -r '.result.agentInfo.version // "?"' 2>/dev/null)
  log "ACP connected: $aname v$aver"

  # Create session — inject MCP servers if configured
  local _mcp_arr="[]"
  if [[ -f "$agent_dir/mcp.json" ]]; then
    _mcp_arr=$(jq -c '[.mcpServers | to_entries[] | {name:.key, command:.value.command, args:.value.args}]' "$agent_dir/mcp.json" 2>/dev/null || echo "[]")
  fi
  _acp_send "{\"jsonrpc\":\"2.0\",\"id\":$_acp_rpc_id,\"method\":\"session/new\",\"params\":{\"workspaceRoots\":[{\"uri\":\"file://$workdir\"}],\"cwd\":\"$workdir\",\"mcpServers\":$_mcp_arr}}"
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

  # ── Runtime: gemini-cli ──
  cat > "$RUNTIMES_DIR/gemini-cli.sh" << 'RTEOF'
#!/bin/bash
# Runtime: gemini-cli bridge
# Each message invokes gemini -p (headless mode) with --yolo auto-approve

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

  local completion_instruction
  if [[ -n "$reply_dir" ]]; then
    completion_instruction="Your output will be automatically returned to the caller. Do NOT run sage send — just do the work and let your output speak for itself."
  else
    completion_instruction="When you complete this task, report your result by running:
sage send $from \"Done: <brief summary of what you did>\""
  fi

  local prompt_file=$(mktemp /tmp/sage-gemini-XXXXX.txt)
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

  [[ -f "$steer_file" ]] && rm -f "$steer_file"

  # Set system prompt via env var
  export GEMINI_SYSTEM_MD="$prompt_file"

  log "invoking gemini-cli..."
  cd "$workdir"

  local gemini_args=(-p --yolo)
  [[ -n "$model" ]] && gemini_args+=(--model "$model")

  local live_output="$agent_dir/.live_output"
  > "$live_output"

  gemini "${gemini_args[@]}" "$(cat "$prompt_file")" 2>&1 | tee -a "$live_output"

  local output
  output=$(cat "$live_output")
  rm -f "$prompt_file"

  log "gemini-cli finished: $(echo "$output" | tail -1 | head -c 120)"

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

  # ── Runtime: codex ──
  cat > "$RUNTIMES_DIR/codex.sh" << 'RTEOF'
#!/bin/bash
# Runtime: codex CLI bridge
# Each message invokes codex exec (non-interactive mode)

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

  local completion_instruction
  if [[ -n "$reply_dir" ]]; then
    completion_instruction="Your output will be automatically returned to the caller. Do NOT run sage send — just do the work and let your output speak for itself."
  else
    completion_instruction="When you complete this task, report your result by running:
sage send $from '{\"status\":\"done\",\"agent\":\"$name\",\"result\":\"<brief summary>\"}'"
  fi

  local prompt
  prompt="$(cat "$instructions" 2>/dev/null)

---
## Current Task (from: $from)
$task
---
$completion_instruction"

  log "invoking codex exec..."
  local output
  cd "$workdir"

  local codex_args=(exec "$prompt")
  [[ -n "$model" ]] && codex_args+=(-m "$model")

  output=$(codex "${codex_args[@]}" 2>&1) || true

  # Strip ANSI escapes
  output=$(printf '%s' "$output" | perl -pe 's/\e\[[0-9;?]*[a-zA-Z]//g; s/\r//g' 2>/dev/null | grep -v '^\s*$')

  log "codex finished: $(echo "$output" | tail -1 | head -c 120)"

  [[ -n "$output" ]] && printf '%s\n' "$output"

  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    local _rtmp="$results_dir/${msg_id}.result.json.tmp"
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$_rtmp" && mv "$_rtmp" "$results_dir/${msg_id}.result.json" || rm -f "$_rtmp"
  fi

  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    local _rptmp="$reply_dir/${msg_id}.json.tmp"
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
TIMEOUT_SECONDS=$(jq -r '.timeout_seconds // 0' "$AGENT_DIR/runtime.json" 2>/dev/null || echo 0)
MAX_TURNS=$(jq -r '.max_turns // 0' "$AGENT_DIR/runtime.json" 2>/dev/null || echo 0)
AGENT_START_TS=$(date +%s)
TURN_COUNT=0

# Validate runtime name (prevent path traversal)
if [[ ! "$RUNTIME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "error: invalid runtime name '$RUNTIME'" >&2
  exit 1
fi

# Load per-agent environment variables
if [[ -f "$AGENT_DIR/env" ]]; then
  while IFS= read -r _envline || [[ -n "$_envline" ]]; do
    [[ -z "$_envline" || "$_envline" == \#* ]] && continue
    export "$_envline"
  done < "$AGENT_DIR/env"
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

    # Max-turns enforcement
    TURN_COUNT=$((TURN_COUNT + 1))
    if [[ "$MAX_TURNS" -gt 0 && "$TURN_COUNT" -ge "$MAX_TURNS" ]]; then
      log "max-turns reached ($TURN_COUNT/$MAX_TURNS) — stopping"
      exit 0
    fi
  done
  sleep 0.3
  # Timeout enforcement
  if [[ "$TIMEOUT_SECONDS" -gt 0 ]]; then
    local elapsed=$(( $(date +%s) - AGENT_START_TS ))
    if [[ $elapsed -ge $TIMEOUT_SECONDS ]]; then
      log "timeout reached (${TIMEOUT_SECONDS}s) — stopping"
      exit 0
    fi
  fi
done
RUNNER
  chmod +x "$SAGE_HOME/runner.sh"

  ok "sage initialized at $SAGE_HOME"
}

# ═══════════════════════════════════════════════
# sage create <name> [--runtime <rt>] [--model <m>]
# ═══════════════════════════════════════════════
cmd_create() {
  local name="" runtime="" model="" parent="" acp_agent="" worktree_branch="" mcp_servers="" skill_name="" from_archive="" timeout_val="" max_turns_val=""
  local -a env_pairs=()
  # Read config defaults (flags override)
  local _cfg_rt; _cfg_rt=$(_config_get default.runtime)
  local _cfg_model; _cfg_model=$(_config_get default.model)
  local _cfg_agent; _cfg_agent=$(_config_get default.agent)
  [[ -n "$_cfg_rt" ]] && runtime="$_cfg_rt"
  [[ -n "$_cfg_model" ]] && model="$_cfg_model"
  [[ -n "$_cfg_agent" ]] && acp_agent="$_cfg_agent"
  : "${runtime:=bash}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --runtime|-r)   runtime="$2"; shift 2 ;;
      --model|-m)     model="$2"; shift 2 ;;
      --agent|-a)     acp_agent="$2"; shift 2 ;;
      --parent)       parent="$2"; shift 2 ;;
      --worktree|-w)  worktree_branch="$2"; shift 2 ;;
      --mcp)          mcp_servers="$2"; shift 2 ;;
      --skill)        skill_name="$2"; shift 2 ;;
      --from)         from_archive="$2"; shift 2 ;;
      --timeout)      timeout_val="$2"; shift 2 ;;
      --max-turns)    max_turns_val="$2"; shift 2 ;;
      --env)          env_pairs+=("$2"); shift 2 ;;
      -*)             die "unknown flag: $1" ;;
      *)              name="$1"; shift ;;
    esac
  done

  [[ -n "$name" ]] || die "usage: sage create <name> [--runtime bash|cline|claude-code|gemini-cli|codex|acp] [--agent <agent>] [--model <model>]"

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

  # Parse --timeout value (Nm=minutes, Nh=hours, Ns/N=seconds)
  local timeout_seconds=""
  if [[ -n "$timeout_val" ]]; then
    case "$timeout_val" in
      *m) timeout_seconds=$(( ${timeout_val%m} * 60 )) ;;
      *h) timeout_seconds=$(( ${timeout_val%h} * 3600 )) ;;
      *s) timeout_seconds="${timeout_val%s}" ;;
      *[0-9]) timeout_seconds="$timeout_val" ;;
      *)  die "invalid timeout '$timeout_val' — use Nm, Nh, Ns, or bare seconds" ;;
    esac
    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die "invalid timeout '$timeout_val' — use Nm, Nh, Ns, or bare seconds"
  fi

  # Parse --max-turns value (must be positive integer)
  local max_turns=""
  if [[ -n "$max_turns_val" ]]; then
    [[ "$max_turns_val" =~ ^[0-9]+$ ]] || die "invalid max-turns '$max_turns_val' — must be a positive integer"
    [[ "$max_turns_val" -gt 0 ]] || die "invalid max-turns '$max_turns_val' — must be a positive integer"
    max_turns="$max_turns_val"
  fi

  # Import from archive if --from specified
  if [[ -n "$from_archive" ]]; then
    # Download from URL if needed
    if [[ "$from_archive" =~ ^https?:// ]]; then
      local url="$from_archive"
      # GitHub repo URL → archive URL
      if [[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/?$ ]]; then
        url="${url%/}/archive/refs/heads/main.tar.gz"
      fi
      local tmp_dl; tmp_dl=$(mktemp "${TMPDIR:-/tmp}/sage-import-XXXXXX.tar.gz")
      if ! curl -fsSL -o "$tmp_dl" "$url" 2>/dev/null; then
        rm -f "$tmp_dl"
        die "download failed: $from_archive"
      fi
      from_archive="$tmp_dl"
      trap "rm -f '$tmp_dl'" RETURN
    fi
    [[ -f "$from_archive" ]] || die "archive not found: $from_archive"
    mkdir -p "$agent_dir"/{inbox,state,replies,workspace}
    tar xzf "$from_archive" -C "$agent_dir"
    local tmp; tmp=$(jq --arg n "$name" '.name=$n | del(.worktree,.worktree_branch,.repo_root)' "$agent_dir/runtime.json") && echo "$tmp" > "$agent_dir/runtime.json"
    ok "imported '$name' from $from_archive"
    return 0
  fi

  # Validate runtime
  [[ -f "$RUNTIMES_DIR/${runtime}.sh" ]] || die "unknown runtime: $runtime (available: $(ls "$RUNTIMES_DIR" | sed 's/.sh//' | tr '\n' ' '))"

  # Validate MCP servers exist in registry
  local mcp_list=()
  if [[ -n "$mcp_servers" ]]; then
    IFS=',' read -ra mcp_list <<< "$mcp_servers"
    for srv in "${mcp_list[@]}"; do
      [[ -f "$SAGE_HOME/mcp/${srv}.json" ]] || die "unknown MCP server: $srv (register with: sage mcp add $srv --command <cmd> --args <args>)"
    done
  fi

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
  local wt="false" wb="" wr=""
  if [[ -n "$worktree_branch" ]]; then wt="true"; wb="$worktree_branch"; wr="$repo_root"; fi
  local mcp_json_arr="[]"
  if [[ ${#mcp_list[@]} -gt 0 ]]; then
    mcp_json_arr=$(printf '%s\n' "${mcp_list[@]}" | jq -R . | jq -s .)
  fi
  jq -n \
    --arg rt "$runtime" \
    --arg m "$model" \
    --arg p "$parent" \
    --arg wd "$agent_dir/workspace" \
    --arg aa "$acp_agent" \
    --argjson wt "$wt" \
    --arg wb "$wb" \
    --arg wr "$wr" \
    --argjson mcp "$mcp_json_arr" \
    --arg to "$timeout_seconds" \
    --arg mt "$max_turns" \
    '{runtime:$rt, model:$m, parent:$p, workdir:$wd, acp_agent:$aa, worktree:$wt, worktree_branch:$wb, repo_root:$wr, mcp_servers:$mcp, created:(now|todate)} | if $to != "" then .timeout_seconds=($to|tonumber) else . end | if $mt != "" then .max_turns=($mt|tonumber) else . end' \
    > "$agent_dir/runtime.json"

  # Assemble mcp.json from registry
  if [[ ${#mcp_list[@]} -gt 0 ]]; then
    local mcp_cfg="{\"mcpServers\":{}}"
    for srv in "${mcp_list[@]}"; do
      mcp_cfg=$(echo "$mcp_cfg" | jq --arg s "$srv" --slurpfile c "$SAGE_HOME/mcp/${srv}.json" '.mcpServers[$s] = $c[0]')
    done
    echo "$mcp_cfg" > "$agent_dir/mcp.json"
  fi

  # Write env vars from --env flags
  if [[ ${#env_pairs[@]} -gt 0 ]]; then
    for pair in "${env_pairs[@]}"; do
      [[ "$pair" == *=* ]] || die "invalid env format '$pair' — use KEY=VALUE"
      echo "$pair"
    done > "$agent_dir/env"
  fi

  # Validate and attach skill
  if [[ -n "$skill_name" ]]; then
    [[ -d "$SKILLS_DIR/$skill_name" ]] || die "skill '$skill_name' not found (install with: sage skill install <source>)"
    jq -n --arg s "$skill_name" '[$s]' > "$agent_dir/skills.json"
  fi

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

  # Start MCP servers if configured
  [[ -f "$AGENTS_DIR/$name/mcp.json" ]] && cmd_mcp start-servers "$name" 2>/dev/null || true

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
  # Stop MCP servers first
  [[ -f "$AGENTS_DIR/$name/.mcp-pids" ]] && cmd_mcp stop-servers "$name" 2>/dev/null || true
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
    tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null || true
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
  local to="" message="" force=false headless=false json_output=false no_context=false
  local then_chain="" retry_max=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f)    force=true; shift ;;
      --headless)    headless=true; shift ;;
      --json)        json_output=true; shift ;;
      --no-context)  no_context=true; shift ;;
      --then)        then_chain="${then_chain:+$then_chain }$2"; shift 2 ;;
      --retry)       retry_max="$2"; shift 2 ;;
      -*)            die "unknown flag: $1" ;;
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

  [[ -n "$to" && -n "$message" ]] || die "usage: sage send <agent> <message|@file> [--force|--headless|--json|--then <agent>]"

  # --then requires --headless
  if [[ -n "$then_chain" && "$headless" != true ]]; then
    die "--then requires --headless (chaining needs synchronous execution)"
  fi
  if [[ "$retry_max" -gt 0 && "$headless" != true ]]; then
    die "--retry requires --headless"
  fi
  if [[ -n "$then_chain" ]]; then
    local _ta
    for _ta in $then_chain; do
      agent_exists "$_ta"
    done
  fi
  ensure_init

  if [[ "$to" != ".cli" ]]; then
    agent_exists "$to"
    # Auto-start if not running (skip for headless — no tmux needed)
    if [[ "$headless" != true ]] && ! agent_pid "$to" >/dev/null 2>&1; then
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

  # Inject skill system_prompt if agent has a skill attached
  if [[ "$to" != ".cli" ]]; then
    local _skill_file="$AGENTS_DIR/$to/skills.json"
    if [[ -f "$_skill_file" ]]; then
      local _sname _sj _sp
      _sname=$(jq -r '.[0] // empty' "$_skill_file" 2>/dev/null) || true
      if [[ -n "$_sname" ]]; then
        _sj="$SKILLS_DIR/$_sname/skill.json"
        if [[ -f "$_sj" ]]; then
          _sp=$(jq -r '.system_prompt // empty' "$_sj")
          [[ -z "$_sp" ]] || message="[System] $_sp

$message"
        fi
      fi
    fi
  fi

  # Auto-inject shared context keys into message
  if [[ "$no_context" != true && -d "$CONTEXT_DIR" ]]; then
    local _ctx_keys _ctx_block=""
    _ctx_keys=$(ls "$CONTEXT_DIR/" 2>/dev/null) || true
    if [[ -n "$_ctx_keys" ]]; then
      while IFS= read -r _ck; do
        _ctx_block="${_ctx_block}${_ck}=$(cat "$CONTEXT_DIR/$_ck")"$'\n'
      done <<< "$_ctx_keys"
      message="[Context]
${_ctx_block}
$message"
    fi
  fi

  # Auto-inject unread messages and clear them
  local _msg_dir="$AGENTS_DIR/$to/messages"
  if [[ -d "$_msg_dir" ]]; then
    local _msg_files _msg_block=""
    _msg_files=$(ls -t "$_msg_dir"/*.json 2>/dev/null) || true
    if [[ -n "$_msg_files" ]]; then
      while IFS= read -r _mf; do
        [[ -f "$_mf" ]] || continue
        local _mfrom _mtext
        _mfrom=$(jq -r '.from' "$_mf")
        _mtext=$(jq -r '.text' "$_mf")
        _msg_block="${_msg_block}${_mfrom}: ${_mtext}"$'\n'
      done <<< "$_msg_files"
      message="[Messages]
${_msg_block}
$message"
      rm -f "$_msg_dir"/*.json
    fi
  fi

  # --headless: run task directly without tmux
  if [[ "$headless" == true ]]; then
    local agent_dir="$AGENTS_DIR/$to"
    local runtime
    runtime=$(jq -r '.runtime // "bash"' "$agent_dir/runtime.json" 2>/dev/null || echo "bash")
    export SAGE_AGENT_NAME="$to"
    export SAGE_HOME
    export AGENTS_DIR
    LOGS="${SAGE_HOME}/logs"; mkdir -p "$LOGS"
    log() { echo "[$(date '+%H:%M:%S')] $SAGE_AGENT_NAME: $*" >> "$LOGS/$SAGE_AGENT_NAME.log"; }
    mkdir -p "$agent_dir/results"

    # Load per-agent environment variables
    if [[ -f "$agent_dir/env" ]]; then
      while IFS= read -r _envline || [[ -n "$_envline" ]]; do
        [[ -z "$_envline" || "$_envline" == \#* ]] && continue
        export "$_envline"
      done < "$agent_dir/env"
    fi

    # Source tools and runtime
    for tool in "$SAGE_HOME/tools"/*.sh; do [[ -f "$tool" ]] && source "$tool"; done
    source "$SAGE_HOME/runtimes/${runtime}.sh"
    runtime_start "$agent_dir" "$to"

    local msg task_id start_ts rc=0
    task_id="headless-$(date +%s)"
    msg=$(jq -n --arg id "$task_id" --arg from "cli" --arg t "$message" '{id:$id,from:$from,payload:{text:$t}}')
    start_ts=$(date +%s)

    local task_output
    task_output=$(runtime_inject "$to" "$msg" 2>&1) || rc=$?

    # Retry on failure
    local _retry_i=0
    while [[ $rc -ne 0 && $_retry_i -lt $retry_max ]]; do
      _retry_i=$((_retry_i + 1))
      log "retry $_retry_i/$retry_max after failure (rc=$rc)"
      sleep 2
      rc=0
      task_output=$(runtime_inject "$to" "$msg" 2>&1) || rc=$?
    done
    local elapsed=$(( $(date +%s) - start_ts ))

    # Write result files so `sage result <task_id>` works
    local _rstatus="done"; [[ $rc -ne 0 ]] && _rstatus="failed"
    local results_dir="$agent_dir/results"; mkdir -p "$results_dir"
    jq -n --arg s "$_rstatus" --arg id "$task_id" --argjson rc "$rc" \
      '{id:$id,status:$s,exit_code:$rc}' > "$results_dir/${task_id}.status.json"
    jq -n --arg out "$task_output" '{output:$out}' > "$results_dir/${task_id}.result.json"

    # Chain to next agent if --then specified
    if [[ -n "$then_chain" && "$_rstatus" == "done" ]]; then
      local _chain_msg="Result from ${to}: ${task_output}"
      local _first _rest
      _first="${then_chain%% *}"
      _rest="${then_chain#"$_first"}"
      _rest="${_rest# }"
      local _chain_cmd=("$0" send "$_first" "$_chain_msg" --headless)
      if [[ -n "$_rest" ]]; then
        local _r
        for _r in $_rest; do
          _chain_cmd+=(--then "$_r")
        done
      fi
      "${_chain_cmd[@]}"
    fi

    if [[ "$json_output" == true ]]; then
      jq -n --arg s "$_rstatus" --arg id "$task_id" --argjson rc "$rc" --argjson el "$elapsed" --arg out "$task_output" \
        '{status:$s,task_id:$id,exit_code:$rc,elapsed:$el,output:$out}'
    else
      [[ -n "$task_output" ]] && printf '%s\n' "$task_output"
    fi
    return $rc
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
  local long=false json=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--long) long=true; shift ;;
      --json) json=true; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  if $json; then
    local first=true
    printf '['
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      local rt=$(jq -r '.runtime // "bash"' "$d/runtime.json" 2>/dev/null || echo "bash")
      local st="stopped"
      agent_pid "$n" >/dev/null 2>&1 && st="running"
      $first || printf ','
      first=false
      printf '{"name":"%s","runtime":"%s","status":"%s"}' "$n" "$rt" "$st"
    done
    printf ']\n'
    return 0
  fi

  if $long; then
    printf "%-16s %-12s %s\n" "NAME" "RUNTIME" "STATUS"
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      local rt=$(jq -r '.runtime // "bash"' "$d/runtime.json" 2>/dev/null || echo "bash")
      local st="stopped"
      agent_pid "$n" >/dev/null 2>&1 && st="running"
      printf "%-16s %-12s %s\n" "$n" "$rt" "$st"
    done
    return 0
  fi

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
  local name="" dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *) name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || die "usage: sage merge <name> [--dry-run]"
  ensure_init; agent_exists "$name"
  local agent_dir="$AGENTS_DIR/$name"
  local is_wt branch
  is_wt=$(jq -r '.worktree // false' "$agent_dir/runtime.json" 2>/dev/null)
  [[ "$is_wt" == "true" ]] || die "agent '$name' is not a worktree agent"
  branch=$(jq -r '.worktree_branch' "$agent_dir/runtime.json")
  local repo_root
  repo_root=$(jq -r '.repo_root // empty' "$agent_dir/runtime.json")
  if [[ -n "$repo_root" ]]; then
    cd "$repo_root" || die "cannot cd to repo root: $repo_root"
  fi
  git rev-parse --show-toplevel >/dev/null 2>&1 || die "not in a git repository"
  if $dry_run; then
    if git merge --no-commit --no-ff "$branch" >/dev/null 2>&1; then
      git diff --cached --stat
      git merge --abort
      ok "merge would be clean for branch '$branch'"
    else
      local conflicts
      conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)
      git merge --abort 2>/dev/null
      die "conflict detected in: $conflicts"
    fi
  else
    git merge "$branch" --no-edit || die "merge conflict — resolve manually then run: git merge --continue"
    ok "merged branch '$branch' from agent '$name'"
  fi
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
  local pattern="" task_template="" inputs=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --save)     save_file="$2"; shift 2 ;;
      --run)      run_file="$2"; shift 2 ;;
      --resume)   resume_file="$2"; shift 2 ;;
      --yes|-y)   auto_approve=true; shift ;;
      --list|-l)  _plan_list; return 0 ;;
      --pattern)  pattern="$2"; shift 2 ;;
      --task)     task_template="$2"; shift 2 ;;
      --inputs)   inputs="$2"; shift 2 ;;
      -*)         die "unknown flag: $1" ;;
      *)          goal="$goal $1"; shift ;;
    esac
  done

  goal=$(echo "$goal" | sed 's/^ *//')
  ensure_init
  mkdir -p "$PLANS_DIR"

  # Pattern-based plan generation (no LLM needed)
  if [[ -n "$pattern" ]]; then
    _plan_pattern "$pattern" "$task_template" "$inputs" "$save_file" "$auto_approve"
    return $?
  fi

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

# Pattern-based plan generation
_plan_pattern() {
  local pattern="$1" task_template="$2" inputs="$3" save_file="$4" auto_approve="$5"

  case "$pattern" in
    fan-out|pipeline|debate|map-reduce) ;;
    *) die "unknown pattern: $pattern (available: fan-out, pipeline, debate, map-reduce)" ;;
  esac

  [[ -n "$inputs" ]] || die "$pattern requires --inputs 'item1,item2,...'"

  local plan_id="plan-$(date +%s)"
  local plan_file="$PLANS_DIR/${plan_id}.json"
  local tasks="[]"
  local id=1

  if [[ "$pattern" == "map-reduce" ]]; then
    [[ -n "$task_template" ]] || die "map-reduce requires --task '<template with {} placeholder>'"
    [[ "$task_template" == *"{}"* ]] || die "map-reduce --task must contain {} placeholder"
    local input_count
    input_count=$(echo "$inputs" | tr ',' '\n' | wc -l | tr -d ' ')
    [[ "$input_count" -ge 2 ]] || die "map-reduce requires at least 2 inputs"
    local IFS=','
    for input in $inputs; do
      input=$(echo "$input" | sed 's/^ *//;s/ *$//')
      local desc="${task_template//\{\}/$input}"
      tasks=$(echo "$tasks" | jq --arg d "$desc" --argjson i "$id" \
        '. + [{"id":$i,"template":"implement","description":$d,"depends":[],"files":[]}]')
      id=$((id + 1))
    done
    local all_deps="[]"
    local dep_id=1
    while [[ "$dep_id" -lt "$id" ]]; do
      all_deps=$(echo "$all_deps" | jq --argjson d "$dep_id" '. + [$d]')
      dep_id=$((dep_id + 1))
    done
    tasks=$(echo "$tasks" | jq --arg d "Reduce: merge all results into a single summary" --argjson i "$id" --argjson dp "$all_deps" \
      '. + [{"id":$i,"template":"implement","description":$d,"depends":$dp,"files":[]}]')
  elif [[ "$pattern" == "debate" ]]; then
    [[ -n "$task_template" ]] || die "debate requires --task '<debate topic>'"
    local input_count
    input_count=$(echo "$inputs" | tr ',' '\n' | wc -l | tr -d ' ')
    [[ "$input_count" -ge 2 ]] || die "debate requires at least 2 participants in --inputs"
    local IFS=','
    for participant in $inputs; do
      participant=$(echo "$participant" | sed 's/^ *//;s/ *$//')
      tasks=$(echo "$tasks" | jq --arg d "$participant: $task_template" --argjson i "$id" \
        '. + [{"id":$i,"template":"implement","description":$d,"depends":[],"files":[]}]')
      id=$((id + 1))
    done
    # Synthesizer depends on all participants
    local all_deps="[]"
    local dep_id=1
    while [[ "$dep_id" -lt "$id" ]]; do
      all_deps=$(echo "$all_deps" | jq --argjson d "$dep_id" '. + [$d]')
      dep_id=$((dep_id + 1))
    done
    tasks=$(echo "$tasks" | jq --arg d "Synthesize: compare all responses and pick the best answer" --argjson i "$id" --argjson dp "$all_deps" \
      '. + [{"id":$i,"template":"implement","description":$d,"depends":$dp,"files":[]}]')
  elif [[ "$pattern" == "pipeline" ]]; then
    [[ -n "$task_template" ]] || die "pipeline requires --task 'Step1 {},Step2 {},...'"
    # Count steps (comma-separated task_template items)
    local step_count
    step_count=$(echo "$task_template" | tr ',' '\n' | wc -l)
    [[ "$step_count" -ge 2 ]] || die "pipeline requires at least 2 steps in --task"
    local IFS=','
    for step in $task_template; do
      step=$(echo "$step" | sed 's/^ *//;s/ *$//')
      local desc="${step//\{\}/$inputs}"
      local deps="[]"
      [[ "$id" -gt 1 ]] && deps="[$((id - 1))]"
      tasks=$(echo "$tasks" | jq --arg d "$desc" --argjson i "$id" --argjson dp "$deps" \
        '. + [{"id":$i,"template":"implement","description":$d,"depends":$dp,"files":[]}]')
      id=$((id + 1))
    done
  else
    [[ -n "$task_template" ]] || die "fan-out requires --task '<template with {} placeholder>'"
    # Split inputs by comma
    local IFS=','
    for input in $inputs; do
      input=$(echo "$input" | sed 's/^ *//;s/ *$//')
      local desc="${task_template//\{\}/$input}"
      tasks=$(echo "$tasks" | jq --arg d "$desc" --argjson i "$id" \
        '. + [{"id":$i,"template":"implement","description":$d,"depends":[],"files":[]}]')
      id=$((id + 1))
    done
  fi

  jq -n --arg g "$pattern: $task_template" --arg id "$plan_id" --argjson t "$tasks" \
    '{goal:$g, plan_id:$id, status:"pending", tasks:$t}' > "$plan_file"

  if [[ -n "$save_file" ]]; then
    cp "$plan_file" "$save_file"
    ok "plan saved to $save_file"
  fi

  _plan_display "$plan_file"

  if [[ "$auto_approve" == true ]]; then
    _plan_execute "$plan_file" "fresh"
    return $?
  fi

  echo ""
  printf "  ${BOLD}[a]${NC}pprove  ${BOLD}[r]${NC}eject  "
  read -r choice
  case "$choice" in
    a|approve) _plan_execute "$plan_file" "fresh" ;;
    *) info "plan rejected" ;;
  esac
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
# sage mcp — manage MCP server registry
# ═══════════════════════════════════════════════
cmd_mcp() {
  local subcmd="${1:-}"
  shift 2>/dev/null || true
  ensure_init
  mkdir -p "$SAGE_HOME/mcp"

  case "$subcmd" in
    add)
      local name="" command="" args=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --command) command="$2"; shift 2 ;;
          --args)    args="$2"; shift 2 ;;
          -*)        die "unknown flag: $1" ;;
          *)         name="$1"; shift ;;
        esac
      done
      [[ -n "$name" ]] || die "usage: sage mcp add <name> --command <cmd> [--args <comma-separated>]"
      [[ -n "$command" ]] || die "usage: sage mcp add <name> --command <cmd> [--args <comma-separated>]"
      local args_json="[]"
      if [[ -n "$args" ]]; then
        args_json=$(echo "$args" | tr ',' '\n' | jq -R . | jq -s .)
      fi
      jq -n --arg c "$command" --argjson a "$args_json" '{command:$c, args:$a}' > "$SAGE_HOME/mcp/${name}.json"
      echo "registered MCP server: $name"
      ;;
    rm)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage mcp rm <name>"
      rm -f "$SAGE_HOME/mcp/${name}.json"
      echo "removed MCP server: $name"
      ;;
    ls)
      for f in "$SAGE_HOME/mcp"/*.json; do
        [[ -f "$f" ]] || { echo "no MCP servers registered"; return; }
        local n=$(basename "$f" .json)
        local cmd=$(jq -r '.command' "$f")
        echo "$n  ($cmd)"
      done
      ;;
    start-servers)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage mcp start-servers <agent>"
      agent_exists "$name"
      local rt_file="$AGENTS_DIR/$name/runtime.json"
      local mcp_json="$AGENTS_DIR/$name/mcp.json"
      [[ -f "$mcp_json" ]] || die "$name has no MCP servers configured"
      local pid_file="$AGENTS_DIR/$name/.mcp-pids"
      : > "$pid_file"
      local servers
      servers=$(jq -r '.mcpServers | keys[]' "$mcp_json" 2>/dev/null) || die "invalid mcp.json"
      while IFS= read -r srv; do
        [[ -n "$srv" ]] || continue
        local cmd
        cmd=$(jq -r ".mcpServers[\"$srv\"].command" "$mcp_json")
        # Build args as shell-safe quoted string via jq (portable, no bash arrays)
        local args_shell
        args_shell=$(jq -r "[.mcpServers[\"$srv\"].args[]?] | map(@sh) | join(\" \")" "$mcp_json")
        eval "\"$cmd\" $args_shell" &>/dev/null &
        echo "$srv $!" >> "$pid_file"
        info "started MCP server: $srv (pid $!)"
      done <<< "$servers"
      ok "MCP servers started for $name"
      ;;
    stop-servers)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage mcp stop-servers <agent>"
      agent_exists "$name"
      local pid_file="$AGENTS_DIR/$name/.mcp-pids"
      [[ -f "$pid_file" ]] || { info "$name: no MCP servers running"; return 0; }
      while IFS=' ' read -r srv pid; do
        [[ -n "$pid" ]] || continue
        kill "$pid" 2>/dev/null && info "stopped MCP server: $srv (pid $pid)" || true
      done < "$pid_file"
      rm -f "$pid_file"
      ok "MCP servers stopped for $name"
      ;;
    status)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage mcp status <agent>"
      agent_exists "$name"
      local mcp_json="$AGENTS_DIR/$name/mcp.json"
      [[ -f "$mcp_json" ]] || die "$name has no MCP servers configured"
      local pid_file="$AGENTS_DIR/$name/.mcp-pids"
      if [[ -f "$pid_file" ]]; then
        while IFS=' ' read -r srv pid; do
          [[ -n "$srv" ]] || continue
          if kill -0 "$pid" 2>/dev/null; then
            echo "$srv  pid=$pid  running"
          else
            echo "$srv  pid=$pid  dead"
          fi
        done < "$pid_file"
      else
        echo "$name: MCP servers not running"
      fi
      ;;
    tools)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage mcp tools <agent>"
      agent_exists "$name"
      local mcp_json="$AGENTS_DIR/$name/mcp.json"
      [[ -f "$mcp_json" ]] || die "$name has no MCP servers configured"
      local pid_file="$AGENTS_DIR/$name/.mcp-pids"
      [[ -f "$pid_file" ]] || die "$name: MCP servers not running"
      local servers
      servers=$(jq -r '.mcpServers | keys[]' "$mcp_json" 2>/dev/null) || die "invalid mcp.json"
      while IFS= read -r srv; do
        [[ -n "$srv" ]] || continue
        local cmd
        cmd=$(jq -r ".mcpServers[\"$srv\"].command" "$mcp_json")
        local args_shell
        args_shell=$(jq -r "[.mcpServers[\"$srv\"].args[]?] | map(@sh) | join(\" \")" "$mcp_json")
        # Spawn server, send initialize + tools/list, read response
        local init_req="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"sage\",\"version\":\"$SAGE_VERSION\"}}}"
        local tools_req='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
        local response
        response=$(printf '%s\n%s\n' "$init_req" "$tools_req" | eval "\"$cmd\" $args_shell" 2>/dev/null) || true
        if [[ -n "$response" ]]; then
          local tools_out
          tools_out=$(echo "$response" | jq -r 'select(.result.tools) | .result.tools[] | "  \(.name)  — \(.description // "no description")"' 2>/dev/null) || true
          echo "[$srv]"
          if [[ -n "$tools_out" ]]; then
            echo "$tools_out"
          else
            echo "  (no tools found)"
          fi
        else
          echo "[$srv]  (no response)"
        fi
      done <<< "$servers"
      ;;
    *) die "usage: sage mcp {add|rm|ls|start-servers|stop-servers|status|tools}" ;;
  esac
}

# ═══════════════════════════════════════════════
# sage skill {install|ls|rm}
# ═══════════════════════════════════════════════
cmd_skill() {
  local subcmd="${1:-}"
  shift 2>/dev/null || true
  ensure_init
  mkdir -p "$SKILLS_DIR"

  case "$subcmd" in
    ls)
      local found=0
      for d in "$SKILLS_DIR"/*/skill.json; do
        [[ -f "$d" ]] || continue
        found=1
        local sname sdesc
        sname=$(jq -r '.name // "unknown"' "$d")
        sdesc=$(jq -r '.description // ""' "$d")
        printf "  %-20s %s\n" "$sname" "$sdesc"
      done
      [[ $found -eq 1 ]] || echo "no skills installed"
      ;;
    install)
      local src="${1:-}"
      [[ -n "$src" ]] || die "usage: sage skill install <path-or-repo>"
      # Local directory install
      if [[ -d "$src" ]]; then
        [[ -f "$src/skill.json" ]] || die "no skill.json found in $src"
        local sname
        sname=$(jq -r '.name' "$src/skill.json")
        [[ -n "$sname" && "$sname" != "null" ]] || die "skill.json missing 'name' field"
        cp -r "$src" "$SKILLS_DIR/$sname"
        echo "installed skill: $sname"
      # GitHub repo install (user/repo format)
      elif [[ "$src" == */* ]]; then
        local repo_url="https://github.com/$src.git"
        local tmp_dir
        tmp_dir=$(mktemp -d)
        git clone --depth 1 "$repo_url" "$tmp_dir" 2>/dev/null || die "failed to clone $repo_url"
        [[ -f "$tmp_dir/skill.json" ]] || { rm -rf "$tmp_dir"; die "no skill.json in $repo_url"; }
        local sname
        sname=$(jq -r '.name' "$tmp_dir/skill.json")
        cp -r "$tmp_dir" "$SKILLS_DIR/$sname"
        rm -rf "$tmp_dir"
        echo "installed skill: $sname (from $src)"
      else
        # Bare name — look up in registries
        local _found_repo=""
        for idx in "$REGISTRIES_DIR"/*/index.json; do
          [[ -f "$idx" ]] || continue
          _found_repo=$(jq -r --arg n "$src" '.[] | select(.name==$n) | .repo' "$idx" 2>/dev/null | head -1)
          [[ -n "$_found_repo" ]] && break
        done
        if [[ -n "$_found_repo" ]]; then
          local repo_url="https://github.com/$_found_repo.git"
          local tmp_dir
          tmp_dir=$(mktemp -d)
          git clone --depth 1 "$repo_url" "$tmp_dir" 2>/dev/null || { rm -rf "$tmp_dir"; die "failed to clone $repo_url"; }
          [[ -f "$tmp_dir/skill.json" ]] || { rm -rf "$tmp_dir"; die "no skill.json in $repo_url"; }
          local sname
          sname=$(jq -r '.name' "$tmp_dir/skill.json")
          cp -r "$tmp_dir" "$SKILLS_DIR/$sname"
          rm -rf "$tmp_dir"
          echo "installed skill: $sname (from $_found_repo)"
        else
          die "skill '$src' not found in any registry (try: sage skill search $src)"
        fi
      fi
      ;;
    rm)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage skill rm <name>"
      [[ -d "$SKILLS_DIR/$name" ]] || die "skill '$name' not found"
      rm -rf "$SKILLS_DIR/$name"
      echo "removed skill: $name"
      ;;
    show)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage skill show <name>"
      [[ -d "$SKILLS_DIR/$name" ]] || die "skill '$name' not found"
      local sj="$SKILLS_DIR/$name/skill.json"
      printf "Name:        %s\n" "$(jq -r '.name' "$sj")"
      printf "Version:     %s\n" "$(jq -r '.version // "-"' "$sj")"
      printf "Description: %s\n" "$(jq -r '.description // "-"' "$sj")"
      local sp
      sp=$(jq -r '.system_prompt // empty' "$sj")
      [[ -n "$sp" ]] && printf "Prompt:      %s\n" "$sp"
      local tkeys
      tkeys=$(jq -r '.templates // {} | keys[]' "$sj" 2>/dev/null) || true
      if [[ -n "$tkeys" ]]; then
        echo "Templates:"
        while IFS= read -r tk; do
          printf "  %-15s %s\n" "$tk" "$(jq -r ".templates[\"$tk\"]" "$sj")"
        done <<< "$tkeys"
      fi
      ;;
    run)
      local agent="${1:-}" template="${2:-}"
      [[ -n "$agent" && -n "$template" ]] || die "usage: sage skill run <agent> <template>"
      agent_exists "$agent"
      local agent_dir="$AGENTS_DIR/$agent"
      [[ -f "$agent_dir/skills.json" ]] || die "no skill attached to agent '$agent'"
      local sname
      sname=$(jq -r '.[0]' "$agent_dir/skills.json")
      [[ -d "$SKILLS_DIR/$sname" ]] || die "skill '$sname' not found"
      local sj="$SKILLS_DIR/$sname/skill.json"
      local tmsg
      tmsg=$(jq -r ".templates[\"$template\"] // empty" "$sj")
      [[ -n "$tmsg" ]] || die "template '$template' not found in skill '$sname'"
      local sp
      sp=$(jq -r '.system_prompt // empty' "$sj")
      local full_msg="$tmsg"
      [[ -n "$sp" ]] && full_msg="[System] $sp

$tmsg"
      cmd_send "$agent" "$full_msg" --headless
      ;;
    search)
      local query="${1:-}"
      [[ -n "$query" ]] || die "usage: sage skill search <query>"
      local found=0
      for idx in "$REGISTRIES_DIR"/*/index.json; do
        [[ -f "$idx" ]] || continue
        local matches
        matches=$(jq -r --arg q "$query" '[.[] | select((.name | test($q;"i")) or (.description | test($q;"i")) or (.tags[]? | test($q;"i")))] | .[] | "\(.name)\t\(.repo)\t\(.description)"' "$idx" 2>/dev/null) || true
        while IFS=$'\t' read -r sn sr sd; do
          [[ -n "$sn" ]] || continue
          found=1
          printf "  %-25s %-30s %s\n" "$sn" "$sr" "$sd"
        done <<< "$matches"
      done
      [[ $found -eq 1 ]] || echo "no matching skills found"
      ;;
    registry)
      local rsub="${1:-}"
      shift 2>/dev/null || true
      local _default_reg="youwangd/sage-skills"
      case "$rsub" in
        ls)
          echo "  $_default_reg (default)"
          local rfile="$SAGE_HOME/registries.json"
          if [[ -f "$rfile" ]]; then
            jq -r '.[]' "$rfile" 2>/dev/null | while IFS= read -r r; do
              echo "  $r"
            done
          fi
          ;;
        add)
          local reg="${1:-}"
          [[ -n "$reg" ]] || die "usage: sage skill registry add <user/repo>"
          local rfile="$SAGE_HOME/registries.json"
          [[ -f "$rfile" ]] || echo '[]' > "$rfile"
          if [[ "$reg" == "$_default_reg" ]] || jq -e --arg r "$reg" 'index($r) != null' "$rfile" >/dev/null 2>&1; then
            die "registry '$reg' already added"
          fi
          jq --arg r "$reg" '. + [$r]' "$rfile" > "$rfile.tmp" && mv "$rfile.tmp" "$rfile"
          echo "added registry: $reg"
          ;;
        rm)
          local reg="${1:-}"
          [[ -n "$reg" ]] || die "usage: sage skill registry rm <user/repo>"
          local rfile="$SAGE_HOME/registries.json"
          if [[ ! -f "$rfile" ]] || ! jq -e --arg r "$reg" 'index($r) != null' "$rfile" >/dev/null 2>&1; then
            die "registry '$reg' not found"
          fi
          jq --arg r "$reg" 'map(select(. != $r))' "$rfile" > "$rfile.tmp" && mv "$rfile.tmp" "$rfile"
          echo "removed registry: $reg"
          ;;
        *) die "usage: sage skill registry {ls|add|rm}" ;;
      esac
      ;;
    *) die "usage: sage skill {install|ls|rm|show|run|search|registry}" ;;
  esac
}

# ═══════════════════════════════════════════════
# sage help
# ═══════════════════════════════════════════════
# ═══ Doctor ═══
cmd_doctor() {
  local fails=0
  _doc_check() {
    local label="$1" ok="$2" msg="$3"
    if [[ "$ok" == "1" ]]; then
      echo -e "${GREEN}✓${NC} $label — $msg"
    elif [[ "$ok" == "w" ]]; then
      echo -e "${YELLOW}⚠${NC} $label — $msg"
    else
      echo -e "${RED}✗${NC} $label — $msg"
      fails=$((fails + 1))
    fi
  }

  echo -e "${BOLD}sage doctor${NC}"
  echo ""

  # bash version
  local bv="${BASH_VERSINFO[0]}"
  if [[ "$bv" -ge 4 ]]; then
    _doc_check "bash" 1 "v${BASH_VERSION}"
  else
    _doc_check "bash" "w" "v${BASH_VERSION} (4+ recommended)"
  fi

  # jq
  if command -v jq >/dev/null 2>&1; then
    _doc_check "jq" 1 "$(jq --version 2>&1)"
  else
    _doc_check "jq" 0 "not found"
  fi

  # tmux
  if command -v tmux >/dev/null 2>&1; then
    _doc_check "tmux" 1 "$(tmux -V 2>&1)"
  else
    _doc_check "tmux" "w" "not found (needed for interactive sessions)"
  fi

  # curl (optional)
  if command -v curl >/dev/null 2>&1; then
    _doc_check "curl" 1 "available"
  else
    _doc_check "curl" "w" "not found (needed for API calls)"
  fi

  # sage init
  if [[ -d "$SAGE_HOME/agents" ]]; then
    _doc_check "sage init" 1 "$SAGE_HOME"
  else
    _doc_check "sage init" "w" "not initialized — run: sage init"
  fi

  # stale agent pids
  local stale=0
  if [[ -d "$AGENTS_DIR" ]]; then
    for pidfile in "$AGENTS_DIR"/*/.pid; do
      [[ -f "$pidfile" ]] || continue
      local pid
      pid=$(cat "$pidfile")
      if ! kill -0 "$pid" 2>/dev/null; then
        local aname
        aname=$(basename "$(dirname "$pidfile")")
        echo -e "  ${YELLOW}⚠${NC} stale pid for agent '$aname' (pid $pid)"
        stale=$((stale + 1))
      fi
    done
  fi
  if [[ "$stale" -gt 0 ]]; then
    _doc_check "agents" "w" "$stale stale pid(s) — run: sage clean"
  elif [[ -d "$AGENTS_DIR" ]]; then
    _doc_check "agents" 1 "no stale pids"
  fi

  echo ""
  if [[ "$fails" -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
  else
    echo -e "${RED}$fails issue(s) found.${NC}"
  fi
  return "$fails"
}

cmd_upgrade() {
  local check_only=false
  [[ "${1:-}" == "--check" ]] && check_only=true
  local repo="youwangd/SageCLI" script_path
  script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  local remote_ver
  remote_ver=$(curl -fsSL "https://raw.githubusercontent.com/$repo/main/sage" 2>/dev/null | grep -m1 '^SAGE_VERSION=' | cut -d'"' -f2) || die "failed to fetch remote version"
  info "local:  $SAGE_VERSION"
  info "remote: $remote_ver"
  if [[ "$SAGE_VERSION" == "$remote_ver" ]]; then
    info "already up to date"
    return 0
  fi
  if [[ "$check_only" == true ]]; then
    info "update available: $SAGE_VERSION → $remote_ver"
    return 0
  fi
  info "upgrading $SAGE_VERSION → $remote_ver ..."
  local tmp
  tmp=$(mktemp)
  curl -fsSL "https://raw.githubusercontent.com/$repo/main/sage" -o "$tmp" || { rm -f "$tmp"; die "download failed"; }
  chmod +x "$tmp"
  mv "$tmp" "$script_path" || die "failed to replace $script_path (try with sudo)"
  info "upgraded to $remote_ver ✓"
}

cmd_diff() {
  local name="" git_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stat)   git_args+=("--stat"); shift ;;
      --cached) git_args+=("--cached"); shift ;;
      -*) die "unknown flag: $1" ;;
      *)  name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || die "usage: sage diff <name> [--stat] [--cached]"
  ensure_init
  local agent_dir="$AGENTS_DIR/$name"
  [[ -d "$agent_dir" ]] || die "agent '$name' not found"
  local is_wt
  is_wt=$(jq -r '.worktree // false' "$agent_dir/runtime.json" 2>/dev/null)
  [[ "$is_wt" == "true" ]] || die "agent '$name' is not a worktree agent"
  git -C "$agent_dir/workspace" diff ${git_args[@]+"${git_args[@]}"}
}

cmd_completions() {
  local shell="${1:-}"
  local cmds="attach call clean clone completions config context create diff doctor env export help history inbox info init logs ls mcp merge msg peek plan rename restart result rm runs send skill start stats status steer stop task tasks tool trace upgrade version wait"
  case "$shell" in
    bash)
      cat <<'BASH_COMP'
_sage_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local cmds="attach call clean clone completions config context create diff doctor env export help history inbox info init logs ls mcp merge msg peek plan rename restart result rm runs send skill start stats status steer stop task tasks tool trace upgrade version wait"
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
    return
  fi
  case "$prev" in
    send|start|stop|restart|attach|peek|logs|rm|info|steer|wait|diff|merge|clone|rename|result|export|env|msg)
      local agents=""
      if [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]]; then
        agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
      fi
      COMPREPLY=($(compgen -W "$agents" -- "$cur"));;
    create)
      COMPREPLY=($(compgen -W "--runtime --worktree --mcp --skill --env --timeout --max-turns --from" -- "$cur"));;
    --runtime)
      COMPREPLY=($(compgen -W "bash claude-code cline gemini-cli codex kiro acp" -- "$cur"));;
    skill)
      COMPREPLY=($(compgen -W "install ls rm show run search registry" -- "$cur"));;
    mcp)
      COMPREPLY=($(compgen -W "add ls rm tools" -- "$cur"));;
    context)
      COMPREPLY=($(compgen -W "set get ls rm clear" -- "$cur"));;
    config)
      COMPREPLY=($(compgen -W "set get ls rm" -- "$cur"));;
  esac
}
complete -F _sage_completions sage
BASH_COMP
      ;;
    zsh)
      cat <<'ZSH_COMP'
_sage() {
  local -a commands=(
    'attach:Attach to agent tmux session'
    'call:Send task and wait for result'
    'clean:Remove stopped agents'
    'clone:Duplicate agent config'
    'completions:Generate shell completions'
    'config:Manage user defaults'
    'context:Shared key-value store'
    'create:Create a new agent'
    'diff:Show worktree changes'
    'doctor:Health check'
    'env:Per-agent environment'
    'export:Package agent as archive'
    'help:Show help'
    'history:Activity timeline'
    'info:Agent details'
    'init:Initialize sage'
    'logs:View agent logs'
    'ls:List agents'
    'mcp:MCP server management'
    'merge:Merge worktree branch'
    'msg:Inter-agent messaging'
    'plan:Orchestrate multi-agent plan'
    'rename:Rename an agent'
    'restart:Restart agent'
    'result:Get task result'
    'rm:Remove agent'
    'runs:List task runs'
    'send:Send task to agent'
    'skill:Skills management'
    'start:Start agent'
    'stats:Usage statistics'
    'status:Agent status'
    'steer:Steer running agent'
    'stop:Stop agent'
    'task:Task management'
    'tasks:List tasks'
    'tool:Run agent tool'
    'trace:Trace agent execution'
    'upgrade:Self-update'
    'wait:Wait for agent completion'
  )
  _describe 'sage command' commands
}
compdef _sage sage
ZSH_COMP
      ;;
    *) die "usage: sage completions <bash|zsh>";;
  esac
}

cmd_rename() {
  local old="${1:-}" new="${2:-}"
  [[ -n "$old" && -n "$new" ]] || die "usage: sage rename <old> <new>"
  ensure_init
  [[ "$new" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid agent name '$new'"
  agent_exists "$old"
  [[ ! -d "$AGENTS_DIR/$new" ]] || die "agent '$new' already exists"
  if agent_pid "$old" >/dev/null 2>&1; then
    die "agent '$old' is running — stop it first"
  fi
  mv "$AGENTS_DIR/$old" "$AGENTS_DIR/$new"
  local tmp; tmp=$(jq --arg n "$new" '.name=$n' "$AGENTS_DIR/$new/runtime.json") && echo "$tmp" > "$AGENTS_DIR/$new/runtime.json"
  ok "renamed '$old' → '$new'"
}

cmd_clone() {
  local src="${1:-}" dest="${2:-}"
  [[ -n "$src" && -n "$dest" ]] || die "usage: sage clone <source> <dest>"
  ensure_init
  local src_dir="$AGENTS_DIR/$src" dest_dir="$AGENTS_DIR/$dest"
  [[ -d "$src_dir" ]] || die "agent '$src' not found"
  [[ ! -d "$dest_dir" ]] || die "agent '$dest' already exists"
  [[ "$dest" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid agent name '$dest'"
  mkdir -p "$dest_dir"/{inbox,state,replies,workspace}
  cp "$src_dir/runtime.json" "$dest_dir/runtime.json"
  local tmp; tmp=$(jq --arg n "$dest" '.name=$n | del(.worktree,.worktree_branch,.repo_root)' "$dest_dir/runtime.json") && echo "$tmp" > "$dest_dir/runtime.json"
  for f in system_prompt mcp.json handler.sh; do
    [[ -f "$src_dir/$f" ]] && cp "$src_dir/$f" "$dest_dir/$f"
  done
  [[ -d "$src_dir/skills" ]] && cp -r "$src_dir/skills" "$dest_dir/skills"
  ok "cloned '$src' → '$dest'"
}

cmd_export() {
  local name="" output="" format="tar"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output|-o) output="$2"; shift 2 ;;
      --format)    format="$2"; shift 2 ;;
      -*) die "unknown flag: $1" ;;
      *)  name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || die "usage: sage export <name> [--output file.tar.gz] [--format json]"
  ensure_init
  local agent_dir="$AGENTS_DIR/$name"
  [[ -d "$agent_dir" ]] || die "agent '$name' not found"
  if [[ "$format" == "json" ]]; then
    local json skills_json="[]" sp=""
    json=$(cat "$agent_dir/runtime.json")
    if [[ -f "$agent_dir/system_prompt" ]]; then
      sp=$(cat "$agent_dir/system_prompt")
      json=$(jq --arg sp "$sp" '{runtime: ., system_prompt: $sp}' <<< "$json")
    else
      json=$(jq '{runtime: ., system_prompt: null}' <<< "$json")
    fi
    if [[ -d "$agent_dir/skills" ]]; then
      skills_json=$(ls "$agent_dir/skills" 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))')
    fi
    jq --argjson skills "$skills_json" '. + {skills: $skills}' <<< "$json"
    return
  fi
  : "${output:=${name}.tar.gz}"
  tar czf "$output" -C "$agent_dir" --exclude='state' --exclude='workspace' --exclude='inbox' --exclude='replies' .
  ok "exported '$name' → $output"
}

cmd_help() {
  cat << 'EOF'

  ⚡ sage — Simple Agent Engine

  USAGE
    sage <command> [args]
    sage --version              Show version

  AGENTS
    init [--force]              Initialize sage (~/.sage/)
    create <name> [flags]       Create agent (--runtime bash|cline|claude-code|gemini-cli|codex|acp, --agent <a>, --model <m>)
    start [name|--all]          Start agent(s) in tmux
    stop [name|--all]           Stop agent(s)
    restart [name|--all]        Restart agent(s)
    status                      Show all agents
    ls                          List agent names
    clone <src> <dest>          Duplicate agent config (no state)
    completions <bash|zsh>      Generate shell tab-completions
    rename <old> <new>         Rename an agent
    diff <name> [--stat|--cached] Show git changes in agent worktree
    export <name> [--output f]  Export agent config as tar.gz archive
                  [--format json]  JSON export for programmatic use
    rm <name>                   Remove agent
    clean                       Clean up stale files
    doctor                      Check dependencies and environment health
    history [--agent a] [-n N]  Show agent activity timeline (--json for JSON)
    info <name>                 Show full agent configuration and status (--json)
    upgrade [--check]           Self-update from GitHub (--check: compare only)
    config {set|get|ls|rm}      Persistent user defaults (e.g. default.runtime)

  MESSAGING
    send <to> <message|@file> [--force] Fire-and-forget (--force cancels, --then <agent> chains)
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
    plan --pattern <p> ...      Swarm pattern (fan-out, pipeline, debate, map-reduce)
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


# ═══ Info ═══
cmd_info() {
  local name="" json_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      -*)     die "usage: sage info <name> [--json]" ;;
      *)      name="$1"; shift ;;
    esac
  done
  [[ -n "$name" ]] || die "usage: sage info <name> [--json]"
  ensure_init; agent_exists "$name"

  local agent_dir="$AGENTS_DIR/$name"
  local runtime model pid_text status_text mcp_servers skills worktree disk

  runtime=$(jq -r '.runtime // "bash"' "$agent_dir/runtime.json" 2>/dev/null || echo "bash")
  model=$(jq -r '.model // "default"' "$agent_dir/runtime.json" 2>/dev/null || echo "default")

  if agent_pid "$name" >/dev/null 2>&1; then
    status_text="running (pid $(agent_pid "$name"))"
  else
    status_text="stopped"
  fi

  # MCP servers
  mcp_servers="none"
  [[ -f "$agent_dir/mcp.json" ]] && mcp_servers=$(jq -r '.[]' "$agent_dir/mcp.json" 2>/dev/null | paste -sd', ' -) && [[ -z "$mcp_servers" ]] && mcp_servers="none"

  # Skills
  skills="none"
  [[ -f "$agent_dir/skills.json" ]] && skills=$(jq -r '.[]' "$agent_dir/skills.json" 2>/dev/null | paste -sd', ' -) && [[ -z "$skills" ]] && skills="none"

  # Worktree
  worktree="none"
  [[ -f "$agent_dir/.worktree_branch" ]] && worktree=$(cat "$agent_dir/.worktree_branch")

  # Disk usage
  disk=$(du -sh "$agent_dir" 2>/dev/null | cut -f1 || echo "?")

  # Timeout
  local timeout_display="none"
  local timeout_sec
  timeout_sec=$(jq -r '.timeout_seconds // 0' "$agent_dir/runtime.json" 2>/dev/null || echo 0)
  if [[ "$timeout_sec" -gt 0 ]]; then
    if [[ $((timeout_sec % 3600)) -eq 0 ]]; then timeout_display="$((timeout_sec / 3600))h"
    elif [[ $((timeout_sec % 60)) -eq 0 ]]; then timeout_display="$((timeout_sec / 60))m"
    else timeout_display="${timeout_sec}s"
    fi
  fi

  # Max turns
  local max_turns_display="none"
  local max_turns_val
  max_turns_val=$(jq -r '.max_turns // 0' "$agent_dir/runtime.json" 2>/dev/null || echo 0)
  [[ "$max_turns_val" -gt 0 ]] && max_turns_display="$max_turns_val"

  # Env vars
  local env_count=0
  [[ -f "$agent_dir/env" ]] && env_count=$(grep -c '.' "$agent_dir/env" 2>/dev/null || echo 0)

  # Recent tasks (last 5)
  local tasks_json="[]"
  if ls "$agent_dir"/results/*.status.json >/dev/null 2>&1; then
    tasks_json=$(cat "$agent_dir"/results/*.status.json 2>/dev/null | jq -s 'sort_by(.queued_at // .finished_at // "") | reverse | .[:5]' 2>/dev/null || echo "[]")
  fi

  if $json_mode; then
    jq -n \
      --arg name "$name" --arg runtime "$runtime" --arg model "$model" \
      --arg status "$status_text" --arg mcp "$mcp_servers" --arg skills "$skills" \
      --arg worktree "$worktree" --arg disk "$disk" --argjson tasks "$tasks_json" \
      --arg timeout "$timeout_display" --argjson timeout_sec "$timeout_sec" \
      --argjson max_turns "$max_turns_val" \
      --argjson env_vars "$env_count" \
      '{name:$name, runtime:$runtime, model:$model, status:$status, mcp_servers:($mcp|split(", ")), skills:($skills|split(", ")), worktree:$worktree, disk:$disk, timeout:$timeout, timeout_seconds:$timeout_sec, max_turns:$max_turns, env_vars:$env_vars, recent_tasks:$tasks}'
    return
  fi

  printf "\n${BOLD}  ⚡ %s${NC}\n\n" "$name"
  printf "  %-14s %s\n" "Runtime:" "$runtime"
  printf "  %-14s %s\n" "Model:" "$model"
  printf "  %-14s %s\n" "Status:" "$status_text"
  printf "  %-14s %s\n" "MCP Servers:" "$mcp_servers"
  printf "  %-14s %s\n" "Skills:" "$skills"
  printf "  %-14s %s\n" "Worktree:" "$worktree"
  printf "  %-14s %s\n" "Timeout:" "$timeout_display"
  printf "  %-14s %s\n" "Max Turns:" "$max_turns_display"
  printf "  %-14s %s\n" "Env Vars:" "$env_count"
  printf "  %-14s %s\n" "Disk:" "$disk"

  local task_count
  task_count=$(echo "$tasks_json" | jq 'length' 2>/dev/null || echo 0)
  if [[ "$task_count" -gt 0 ]]; then
    printf "\n  ${BOLD}Recent Tasks:${NC}\n"
    echo "$tasks_json" | jq -r '.[] | "  \(.status // "?")  \(.id // "?")  \(.queued_at // "?")"' 2>/dev/null
  fi
  echo
}
# ═══ History ═══
cmd_history() {
  ensure_init
  local agent_filter="" limit=20 json_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent_filter="$2"; shift 2 ;;
      -n)      limit="$2"; shift 2 ;;
      --json)  json_mode=true; shift ;;
      *)       die "usage: sage history [--agent <name>] [-n <count>] [--json]" ;;
    esac
  done
  local entries=""
  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local aname=$(basename "$agent_dir")
    [[ "$aname" == ".cli" ]] && continue
    [[ -n "$agent_filter" && "$aname" != "$agent_filter" ]] && continue
    for sf in "$agent_dir"results/*.status.json; do
      [[ -f "$sf" ]] || continue
      local line
      line=$(jq -r --arg a "$aname" '. + {agent:$a} | "\(.queued_at // 0)|\(.agent)|\(.id)|\(.status)|\(.started_at // "")|\(.finished_at // "")"' "$sf" 2>/dev/null) || continue
      entries="$entries$line
"
    done
  done
  entries=$(echo "$entries" | grep -v '^$' | sort -t'|' -k1 -rn | head -n "$limit") || true
  if [[ -z "$entries" ]]; then
    info "no task history found"
    return 0
  fi
  if $json_mode; then
    local jarr="["
    local first=true
    while IFS='|' read -r ts agent tid st started finished; do
      local dur="null"
      if [[ "$st" == "done" && -n "$finished" && "$finished" != "null" && -n "$started" && "$started" != "null" ]]; then
        dur=$((finished - started))
      fi
      $first || jarr="$jarr,"
      first=false
      jarr="$jarr{\"agent\":\"$agent\",\"id\":\"$tid\",\"status\":\"$st\",\"queued_at\":$ts,\"duration\":$dur}"
    done <<< "$entries"
    echo "${jarr}]"
    return 0
  fi
  printf "  %-12s %-10s %-8s %s\n" "AGENT" "TASK" "STATUS" "DURATION"
  while IFS='|' read -r ts agent tid st started finished; do
    local dur="-"
    if [[ "$st" == "done" && -n "$finished" && "$finished" != "null" && -n "$started" && "$started" != "null" ]]; then
      dur="$((finished - started))s"
    fi
    printf "  %-12s %-10s %-8s %s\n" "$agent" "$tid" "$st" "$dur"
  done <<< "$entries"
}

# ═══ Stats ═══
cmd_stats() {
  ensure_init
  local json_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      *) die "usage: sage stats [--json]" ;;
    esac
  done

  local total_agents=0 running=0 stopped=0
  local tasks_done=0 tasks_failed=0 tasks_pending=0 total_secs=0
  local most_active_agent="" most_active_count=0

  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local aname; aname=$(basename "$agent_dir")
    [[ "$aname" == ".cli" ]] && continue
    total_agents=$((total_agents + 1))
    if agent_pid "$aname" >/dev/null 2>&1; then
      running=$((running + 1))
    else
      stopped=$((stopped + 1))
    fi
    local agent_tasks=0
    for sf in "$agent_dir"results/*.status.json; do
      [[ -f "$sf" ]] || continue
      local st; st=$(jq -r '.status // ""' "$sf" 2>/dev/null) || continue
      case "$st" in
        done)    tasks_done=$((tasks_done + 1)); agent_tasks=$((agent_tasks + 1))
                 local sa fa
                 sa=$(jq -r '.started_at // 0' "$sf" 2>/dev/null)
                 fa=$(jq -r '.finished_at // 0' "$sf" 2>/dev/null)
                 [[ "$fa" -gt 0 && "$sa" -gt 0 ]] && total_secs=$((total_secs + fa - sa))
                 ;;
        failed)  tasks_failed=$((tasks_failed + 1)); agent_tasks=$((agent_tasks + 1)) ;;
        *)       tasks_pending=$((tasks_pending + 1)) ;;
      esac
    done
    if [[ "$agent_tasks" -gt "$most_active_count" ]]; then
      most_active_count=$agent_tasks
      most_active_agent=$aname
    fi
  done

  # Format runtime
  local rt_display
  if [[ "$total_secs" -ge 3600 ]]; then
    rt_display="$((total_secs / 3600))h $((total_secs % 3600 / 60))m"
  elif [[ "$total_secs" -ge 60 ]]; then
    rt_display="$((total_secs / 60))m $((total_secs % 60))s"
  else
    rt_display="${total_secs}s"
  fi

  if $json_mode; then
    jq -n --argjson ta "$total_agents" --argjson r "$running" --argjson s "$stopped" \
      --argjson td "$tasks_done" --argjson tf "$tasks_failed" --argjson tp "$tasks_pending" \
      --argjson ts "$total_secs" --arg ma "$most_active_agent" --argjson mc "$most_active_count" \
      '{total_agents:$ta,running:$r,stopped:$s,tasks_done:$td,tasks_failed:$tf,tasks_pending:$tp,total_runtime_secs:$ts,most_active:{agent:$ma,tasks:$mc}}'
    return 0
  fi

  printf "  %-14s %s (%s running, %s stopped)\n" "Agents:" "$total_agents" "$running" "$stopped"
  printf "  %-14s %s done, %s failed, %s pending\n" "Tasks:" "$tasks_done" "$tasks_failed" "$tasks_pending"
  printf "  %-14s %s\n" "Runtime:" "$rt_display"
  if [[ -n "$most_active_agent" ]]; then
    printf "  %-14s %s (%s tasks)\n" "Most Active:" "$most_active_agent" "$most_active_count"
  fi
}

# ═══ Config ═══
cmd_config() {
  ensure_init
  local cf="$SAGE_HOME/config.json"
  [[ -f "$cf" ]] || echo '{}' > "$cf"
  local sub="${1:-}"
  case "$sub" in
    set)
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "usage: sage config set <key> <value>"
      local key="$2"; shift 2; local val="$*"
      [[ "$key" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid key '$key' — use alphanumeric, dash, underscore, dot"
      local tmp; tmp=$(jq --arg k "$key" --arg v "$val" '.[$k]=$v' "$cf") && echo "$tmp" > "$cf"
      ok "set $key = $val"
      ;;
    get)
      [[ -n "${2:-}" ]] || die "usage: sage config get <key>"
      local v; v=$(jq -r --arg k "$2" '.[$k] // empty' "$cf")
      [[ -n "$v" ]] || die "key '$2' not found"
      echo "$v"
      ;;
    ls)
      local keys; keys=$(jq -r 'keys[]' "$cf" 2>/dev/null)
      if [[ -z "$keys" ]]; then info "no config keys set"; else
        while IFS= read -r k; do printf "  %s = %s\n" "$k" "$(jq -r --arg k "$k" '.[$k]' "$cf")"; done <<< "$keys"
      fi
      ;;
    rm)
      [[ -n "${2:-}" ]] || die "usage: sage config rm <key>"
      local v; v=$(jq -r --arg k "$2" '.[$k] // empty' "$cf")
      [[ -n "$v" ]] || die "key '$2' not found"
      local tmp; tmp=$(jq --arg k "$2" 'del(.[$k])' "$cf") && echo "$tmp" > "$cf"
      ok "removed $2"
      ;;
    *) die "usage: sage config {set|get|ls|rm}" ;;
  esac
}

# ═══ Env ═══
cmd_env() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    set)
      local name="${1:-}"; shift 2>/dev/null || true
      [[ -n "$name" ]] || die "usage: sage env set <agent> KEY=VALUE"
      ensure_init; agent_exists "$name"
      local agent_dir="$AGENTS_DIR/$name"
      local env_file="$agent_dir/env"
      [[ $# -gt 0 ]] || die "usage: sage env set <agent> KEY=VALUE"
      for pair in "$@"; do
        [[ "$pair" == *=* ]] || die "invalid format '$pair' — use KEY=VALUE"
        local key="${pair%%=*}"
        # Remove existing key if present, then append
        if [[ -f "$env_file" ]]; then
          local tmp; tmp=$(grep -v "^${key}=" "$env_file" 2>/dev/null || true)
          echo "$tmp" > "$env_file"
        fi
        echo "$pair" >> "$env_file"
        # Clean empty lines
        local cleaned; cleaned=$(grep -v '^$' "$env_file" 2>/dev/null || true)
        echo "$cleaned" > "$env_file"
      done
      ok "set env for $name"
      ;;
    ls)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage env ls <agent>"
      ensure_init; agent_exists "$name"
      local env_file="$AGENTS_DIR/$name/env"
      if [[ ! -f "$env_file" ]] || [[ ! -s "$env_file" ]]; then
        echo "  (no env vars)"; return
      fi
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        local k="${line%%=*}" v="${line#*=}"
        local masked
        if [[ ${#v} -le 4 ]]; then masked="****"
        else masked="${v:0:2}***${v: -1}"
        fi
        echo "  $k=$masked"
      done < "$env_file"
      ;;
    rm)
      local name="${1:-}"; shift 2>/dev/null || true
      local key="${1:-}"
      [[ -n "$name" && -n "$key" ]] || die "usage: sage env rm <agent> KEY"
      ensure_init; agent_exists "$name"
      local env_file="$AGENTS_DIR/$name/env"
      [[ -f "$env_file" ]] || { warn "no env vars for $name"; return; }
      local tmp; tmp=$(grep -v "^${key}=" "$env_file" 2>/dev/null || true)
      echo "$tmp" > "$env_file"
      # Clean empty lines
      local cleaned; cleaned=$(grep -v '^$' "$env_file" 2>/dev/null || true)
      echo "$cleaned" > "$env_file"
      ok "removed $key from $name"
      ;;
    *) die "usage: sage env <set|ls|rm> <agent> [KEY=VALUE|KEY]" ;;
  esac
}

# ═══ Inter-Agent Messaging ═══
cmd_msg() {
  ensure_init
  local sub="${1:-}"
  case "$sub" in
    send)
      [[ -n "${2:-}" && -n "${3:-}" && -n "${4:-}" ]] || die "usage: sage msg send <from> <to> <text>"
      local from="$2" to="$3"; shift 3; local text="$*"
      local to_dir="$AGENTS_DIR/$to"
      [[ -d "$to_dir" ]] || die "agent '$to' not found"
      local msg_dir="$to_dir/messages"
      mkdir -p "$msg_dir"
      local ts=$(date +%s)
      local id="${ts}_${from}"
      cat > "$msg_dir/${id}.json" <<EOF
{"from":"$from","text":$(printf '%s' "$text" | jq -Rs .),"ts":$ts}
EOF
      info "sent message from $from → $to"
      ;;
    ls)
      [[ -n "${2:-}" ]] || die "usage: sage msg ls <agent>"
      local agent="$2" format="pretty"
      [[ "${3:-}" == "--json" ]] && format="json"
      local msg_dir="$AGENTS_DIR/$agent/messages"
      local files=""
      if [[ -d "$msg_dir" ]]; then
        files=$(ls -t "$msg_dir"/*.json 2>/dev/null || true)
      fi
      if [[ -z "$files" ]]; then
        if [[ "$format" == "json" ]]; then echo "[]"; else info "no messages for $agent"; fi
        return
      fi
      if [[ "$format" == "json" ]]; then
        printf '['
        local first=true
        for f in $files; do
          [[ -f "$f" ]] || continue
          $first || printf ','
          cat "$f"
          first=false
        done
        printf ']\n'
      else
        for f in $files; do
          [[ -f "$f" ]] || continue
          local mfrom=$(jq -r '.from' "$f")
          local mtext=$(jq -r '.text' "$f")
          local mts=$(jq -r '.ts' "$f")
          local time_str=$(date -d "@$mts" '+%H:%M:%S' 2>/dev/null || echo "—")
          printf "\n  ${BOLD}[%s]${NC} from ${CYAN}%s${NC}\n  %s\n" "$time_str" "$mfrom" "$mtext"
        done
      fi
      ;;
    clear)
      [[ -n "${2:-}" ]] || die "usage: sage msg clear <agent>"
      local msg_dir="$AGENTS_DIR/$2/messages"
      local count=0
      if [[ -d "$msg_dir" ]]; then
        count=$(find "$msg_dir" -name "*.json" 2>/dev/null | wc -l)
        rm -f "$msg_dir"/*.json
      fi
      info "cleared $count message(s) for $2"
      ;;
    *) die "usage: sage msg {send|ls|clear}" ;;
  esac
}

# ═══ Context Store ═══
cmd_context() {
  ensure_init
  mkdir -p "$CONTEXT_DIR"
  local sub="${1:-}"
  case "$sub" in
    set)
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "usage: sage context set <key> <value>"
      local key="$2"; shift 2; local val="$*"
      [[ "$key" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid key '$key' — use alphanumeric, dash, underscore, dot"
      printf '%s' "$val" > "$CONTEXT_DIR/$key"
      info "set $key"
      ;;
    get)
      [[ -n "${2:-}" ]] || die "usage: sage context get <key>"
      [[ -f "$CONTEXT_DIR/$2" ]] || die "key '$2' not found"
      cat "$CONTEXT_DIR/$2"
      ;;
    ls)
      local keys
      keys=$(ls "$CONTEXT_DIR/" 2>/dev/null)
      if [[ -z "$keys" ]]; then
        info "no context keys stored"
      else
        for k in $keys; do
          printf "  %s = %s\n" "$k" "$(cat "$CONTEXT_DIR/$k")"
        done
      fi
      ;;
    rm)
      [[ -n "${2:-}" ]] || die "usage: sage context rm <key>"
      [[ -f "$CONTEXT_DIR/$2" ]] || die "key '$2' not found"
      rm "$CONTEXT_DIR/$2"
      info "removed $2"
      ;;
    clear)
      rm -f "$CONTEXT_DIR"/* 2>/dev/null
      info "cleared all context"
      ;;
    *) die "usage: sage context {set|get|ls|rm|clear}" ;;
  esac
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
  ls)      shift; cmd_ls "$@" ;;
  rm)      cmd_rm "${2:-}" ;;
  clone)   shift; cmd_clone "$@" ;;
  rename)  shift; cmd_rename "$@" ;;
  completions) shift; cmd_completions "$@" ;;
  diff)    shift; cmd_diff "$@" ;;
  export)  shift; cmd_export "$@" ;;
  merge)   shift; cmd_merge "$@" ;;
  clean)   cmd_clean ;;
  tool)    shift; cmd_tool "$@" ;;
  mcp)     shift; cmd_mcp "$@" ;;
  skill)   shift; cmd_skill "$@" ;;
  context) shift; cmd_context "$@" ;;
  msg)     shift; cmd_msg "$@" ;;
  env)     shift; cmd_env "$@" ;;
  config)  shift; cmd_config "$@" ;;
  task)    shift; cmd_task "$@" ;;
  runs)    shift; cmd_runs "$@" ;;
  plan)    shift; cmd_plan "$@" ;;
  help|-h|--help|"") cmd_help ;;
  doctor) cmd_doctor ;;
  history) shift; cmd_history "$@" ;;
  stats)   shift; cmd_stats "$@" ;;
  info)    shift; cmd_info "$@" ;;
  upgrade) shift; cmd_upgrade "$@" ;;
  version|--version|-v) echo "sage $SAGE_VERSION" ;;
  *)       die "unknown command: $1. Run: sage help" ;;
esac
