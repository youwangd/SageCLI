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
  local _task_text
  _task_text=$(echo "$payload" | jq -r '.text // (.task // "")' 2>/dev/null | head -c 120)
  jq -n \
    --arg id "$task_id" \
    --arg from "$me" \
    --arg status "queued" \
    --arg ts "$(date +%s)" \
    --arg tt "$_task_text" \
    '{id:$id, from:$from, status:$status, queued_at:($ts|tonumber), started_at:null, finished_at:null, task_text:$tt}' \
    > "$results_dir/${task_id}.status.json"

  # Add tags if set via _SAGE_TASK_TAGS
  if [[ -n "${_SAGE_TASK_TAGS:-}" ]]; then
    local _tags_json="[]"
    while IFS= read -r _t; do
      [[ -n "$_t" ]] || continue
      _tags_json=$(echo "$_tags_json" | jq --arg t "$_t" '. + [$t]')
    done <<< "$_SAGE_TASK_TAGS"
    jq --argjson tags "$_tags_json" '.tags=$tags' "$results_dir/${task_id}.status.json" > "${results_dir}/${task_id}.status.json.tmp" \
      && mv "${results_dir}/${task_id}.status.json.tmp" "$results_dir/${task_id}.status.json"
  fi

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
  local _task_text
  _task_text=$(echo "$payload" | jq -r '.text // (.task // "")' 2>/dev/null | head -c 120)
  jq -n \
    --arg id "$task_id" \
    --arg from "$me" \
    --arg status "queued" \
    --arg ts "$(date +%s)" \
    --arg tt "$_task_text" \
    '{id:$id, from:$from, status:$status, queued_at:($ts|tonumber), started_at:null, finished_at:null, task_text:$tt}' \
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
      usage_update)
        local ui uo
        ui=$(echo "$event" | jq -r '.params.update.inputTokens // .params.update.input_tokens // 0' 2>/dev/null)
        uo=$(echo "$event" | jq -r '.params.update.outputTokens // .params.update.output_tokens // 0' 2>/dev/null)
        if [[ "${ui:-0}" -gt 0 || "${uo:-0}" -gt 0 ]]; then
          printf '{"ts":%s,"input":%s,"output":%s}\n' "$(date +%s)" "$ui" "$uo" >> "$AGENTS_DIR/$AGENT_NAME/tokens.jsonl"
        fi
        ;;
      agent_thought_chunk|available_commands_update|current_mode_update) ;;
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

  # ── Runtime: ollama ──
  cat > "$RUNTIMES_DIR/ollama.sh" << 'RTEOF'
#!/bin/bash
# Runtime: ollama (local model via ollama CLI)

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
  local model=$(jq -r '.model // "llama3.2:3b"' "$agent_dir/runtime.json" 2>/dev/null)
  local instructions="$agent_dir/instructions.md"

  local prompt=""
  [[ -f "$instructions" ]] && prompt="$(cat "$instructions")"$'\n\n'
  prompt+="$task"

  log "invoking ollama run $model..."
  local output
  output=$(echo "$prompt" | ollama run "$model" 2>&1) || true

  log "ollama finished: $(echo "$output" | tail -1 | head -c 120)"
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

  # ── Runtime: llama-cpp ──
  cat > "$RUNTIMES_DIR/llama-cpp.sh" << 'RTEOF'
#!/bin/bash
# Runtime: llama-cpp (direct llama.cpp inference via llama-cli)

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
  local model=$(jq -r '.model // empty' "$agent_dir/runtime.json" 2>/dev/null)
  local instructions="$agent_dir/instructions.md"

  [[ -n "$model" ]] || { echo "error: no model specified — use --model /path/to/model.gguf"; return 1; }

  local prompt=""
  [[ -f "$instructions" ]] && prompt="$(cat "$instructions")"$'\n\n'
  prompt+="$task"

  log "invoking llama-cli -m $model..."
  local output
  output=$(echo "$prompt" | llama-cli -m "$model" -f /dev/stdin --log-disable 2>&1) || true

  log "llama-cpp finished: $(echo "$output" | tail -1 | head -c 120)"
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
  local name="" runtime="" model="" parent="" acp_agent="" worktree_branch="" mcp_servers="" skill_name="" from_archive="" timeout_val="" max_turns_val="" allow_env=""
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
      --allow-env)    allow_env="$2"; shift 2 ;;
      -*)             die "unknown flag: $1" ;;
      *)              name="$1"; shift ;;
    esac
  done

  [[ -n "$name" ]] || die "usage: sage create <name> [--runtime bash|cline|claude-code|gemini-cli|codex|ollama|llama-cpp|acp] [--agent <agent>] [--model <model>]"

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

  # Write env var allowlist from --allow-env
  if [[ -n "$allow_env" ]]; then
    echo "$allow_env" | tr ',' '\n' > "$agent_dir/allow-env"
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

  # Enforce max-agents concurrency limit (check before tmux setup)
  if [[ -n "$target" && "$target" != "--all" ]]; then
    local _max_agents=""
    [[ -f "$SAGE_HOME/config.json" ]] && _max_agents=$(jq -r '.["max-agents"] // empty' "$SAGE_HOME/config.json" 2>/dev/null) || true
    if [[ -n "$_max_agents" && "$_max_agents" =~ ^[0-9]+$ ]]; then
      local _running=0
      for _pf in "$AGENTS_DIR"/*/.pid; do
        [[ -f "$_pf" ]] || continue
        kill -0 "$(cat "$_pf")" 2>/dev/null && ((_running++)) || true
      done
      if [[ "$_running" -ge "$_max_agents" ]]; then
        die "concurrency limit reached ($_running/$_max_agents agents running) — increase with: sage config set max-agents N"
      fi
    fi
  fi

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

  # Enforce max-agents concurrency limit
  local _max_agents=""
  [[ -f "$SAGE_HOME/config.json" ]] && _max_agents=$(jq -r '.["max-agents"] // empty' "$SAGE_HOME/config.json" 2>/dev/null) || true
  if [[ -n "$_max_agents" && "$_max_agents" =~ ^[0-9]+$ ]]; then
    local _running=0
    for _pf in "$AGENTS_DIR"/*/.pid; do
      [[ -f "$_pf" ]] || continue
      kill -0 "$(cat "$_pf")" 2>/dev/null && ((_running++)) || true
    done
    if [[ "$_running" -ge "$_max_agents" ]]; then
      die "concurrency limit reached ($_running/$_max_agents agents running) — increase with: sage config set max-agents N"
    fi
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
  local target="" graceful_secs=0 failed_only=false dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --graceful) [[ -n "${2:-}" ]] || die "usage: sage stop [name|--all|--failed] [--graceful <duration>] [--dry-run]"
                  graceful_secs=$(_parse_duration "$2") || die "invalid duration '$2' (use: 5s, 30s, 1m)"
                  shift 2 ;;
      --failed)   failed_only=true; shift ;;
      --dry-run)  dry_run=true; shift ;;
      -*) target="$1"; shift ;;
      *)  target="$1"; shift ;;
    esac
  done
  ensure_init

  if $failed_only; then
    local count=0
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n; n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      agent_pid "$n" >/dev/null 2>&1 || continue
      # latest status file (by finished_at/queued_at) must have non-zero exit_code
      local _latest_status="" _latest_ts=0
      for _sf in "$agent_dir"/results/*.status.json; do
        [[ -f "$_sf" ]] || continue
        local _ts; _ts=$(jq -r '.finished_at // .queued_at // 0' "$_sf" 2>/dev/null)
        [[ -z "$_ts" || "$_ts" == "null" ]] && _ts=0
        if [[ "$_ts" -gt "$_latest_ts" ]]; then _latest_ts="$_ts"; _latest_status="$_sf"; fi
      done
      [[ -z "$_latest_status" ]] && continue
      local _rc; _rc=$(jq -r '.exit_code // 0' "$_latest_status" 2>/dev/null)
      [[ "$_rc" == "0" ]] && continue
      if $dry_run; then echo "  would stop: $n"
      else stop_agent "$n" "$graceful_secs"
      fi
      count=$((count + 1))
    done
    if $dry_run; then ok "dry-run: $count failed running agent(s) would be stopped"
    else ok "stopped $count failed running agent(s)"; fi
    return 0
  fi

  if [[ "$target" == "--all" || -z "$target" ]]; then
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      stop_agent "$n" "$graceful_secs"
    done
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null && info "tmux session closed"
  else
    agent_exists "$target"
    stop_agent "$target" "$graceful_secs"
  fi
}

stop_agent() {
  local name="$1" graceful="${2:-0}" pid
  # Stop MCP servers first
  [[ -f "$AGENTS_DIR/$name/.mcp-pids" ]] && cmd_mcp stop-servers "$name" 2>/dev/null || true
  if pid=$(agent_pid "$name"); then
    local pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    # Safety: never signal our own process group (would kill caller/cron/ACP parent)
    local self_pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
    [[ -n "$pgid" && "$pgid" == "$self_pgid" ]] && pgid=""
    if [[ "$graceful" -gt 0 ]]; then
      # Graceful: SIGTERM first, wait, then SIGKILL
      [[ -n "$pgid" ]] && kill -TERM -- -"$pgid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
      local waited=0
      while [[ "$waited" -lt "$graceful" ]] && kill -0 "$pid" 2>/dev/null; do
        sleep 1; waited=$((waited + 1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        [[ -n "$pgid" ]] && kill -9 -- -"$pgid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$AGENTS_DIR/$name/.pid"
        tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null || true
        ok "force-killed $name after ${graceful}s (pid $pid)"
        return 0
      fi
      rm -f "$AGENTS_DIR/$name/.pid"
      tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null || true
      ok "stopped $name gracefully (pid $pid)"
    else
      # Immediate kill (original behavior)
      if [[ -n "$pgid" ]]; then
        kill -- -"$pgid" 2>/dev/null || true
      fi
      pkill -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      rm -f "$AGENTS_DIR/$name/.pid"
      tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null || true
      ok "stopped $name (pid $pid)"
    fi
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
  local target="" failed_only=false dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --failed) failed_only=true; shift ;;
      --dry-run) dry_run=true; shift ;;
      *) target="$1"; shift ;;
    esac
  done
  [[ -n "$target" || "$failed_only" == true ]] || die "usage: sage restart <name|--all|--failed> [--dry-run]"
  ensure_init

  if [[ "$failed_only" == true ]]; then
    local count=0
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      # Find latest task status
      local latest="" latest_ts=0
      for sf in "$agent_dir"results/*.status.json; do
        [[ -f "$sf" ]] || continue
        local ts; ts=$(jq -r '.finished_at // .queued_at // 0' "$sf" 2>/dev/null)
        [[ -z "$ts" || "$ts" == "null" ]] && ts=0
        if [[ "$ts" -gt "$latest_ts" ]]; then latest_ts="$ts"; latest="$sf"; fi
      done
      [[ -z "$latest" ]] && continue
      local rc; rc=$(jq -r '.exit_code // 0' "$latest" 2>/dev/null)
      [[ "$rc" == "0" ]] && continue
      if $dry_run; then
        echo "  would restart: $n"
      else
        stop_agent "$n" 2>/dev/null
        start_agent "$n"
      fi
      count=$((count + 1))
    done
    if $dry_run; then ok "dry-run: $count failed agent(s) would be restarted"
    else ok "restarted $count failed agent(s)"; fi
    return 0
  fi

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
_status_json() {
  local tmux_running=false
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null && tmux_running=true
  local agents_json="[]" first=true
  local _rows=""
  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local name; name=$(basename "$agent_dir")
    [[ "$name" == .* ]] && continue
    local runtime; runtime=$(jq -r '.runtime // "bash"' "$agent_dir/runtime.json" 2>/dev/null || echo "bash")
    local inbox_count; inbox_count=$(find "$agent_dir/inbox" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    local pid status_text pid_val="null"
    if pid=$(agent_pid "$name" 2>/dev/null); then status_text="running"; pid_val="$pid"; else status_text="stopped"; fi
    local logfile="$LOGS_DIR/$name.log"
    local last_active; last_active=$(tail -1 "$logfile" 2>/dev/null | sed -n 's/^\[\([0-9:]*\).*/\1/p')
    [[ -z "$last_active" ]] && last_active=""
    local task_text=""
    local latest_active
    latest_active=$(ls -t "$agent_dir/results/"*.status.json 2>/dev/null | while IFS= read -r sf; do
      local s; s=$(jq -r '.status // ""' "$sf" 2>/dev/null)
      if [[ "$s" == "queued" || "$s" == "running" ]]; then echo "$sf"; break; fi
    done)
    if [[ -n "$latest_active" ]]; then
      task_text=$(jq -r '.task_text // ""' "$latest_active" 2>/dev/null)
      [[ "$task_text" == "null" ]] && task_text=""
    fi
    local row
    row=$(jq -cn --arg name "$name" --arg runtime "$runtime" --arg status "$status_text" \
                 --argjson pid "$pid_val" --argjson inbox "$inbox_count" \
                 --arg task "$task_text" --arg last_active "$last_active" \
                 '{name:$name,runtime:$runtime,status:$status,pid:$pid,inbox:$inbox,task:$task,last_active:$last_active}')
    _rows+="$row"$'\n'
  done
  if [[ -n "$_rows" ]]; then
    agents_json=$(printf '%s' "$_rows" | jq -s .)
  fi
  jq -cn --arg sage_home "$SAGE_HOME" --arg tmux_session "$TMUX_SESSION" \
         --argjson tmux_running "$tmux_running" --argjson agents "$agents_json" \
         '{sage_home:$sage_home,tmux:{session:$tmux_session,running:$tmux_running},agents:$agents}'
}

cmd_status() {
  set +e
  local json_mode=false
  [[ "${1:-}" == "--json" ]] && json_mode=true
  ensure_init

  if $json_mode; then _status_json; return $?; fi

  printf "\n${BOLD}  ⚡ SAGE — Simple Agent Engine${NC}\n"
  printf "  ${DIM}%s${NC}\n\n" "$SAGE_HOME"

  local count=0
  printf "  ${DIM}%-16s %-12s %-10s %-8s %-6s %-24s %s${NC}\n" "AGENT" "RUNTIME" "STATUS" "PID" "INBOX" "TASK" "LAST"

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
    last_active=$(tail -1 "$logfile" 2>/dev/null | sed -n 's/^\[\([0-9:]*\).*/\1/p')
    [[ -z "$last_active" ]] && last_active="—"

    local parent=$(jq -r '.parent // ""' "$agent_dir/runtime.json" 2>/dev/null)
    local display_name="$name"
    [[ -n "$parent" ]] && display_name="  └─ $name"

    # Find active task text from latest queued/running status.json
    local task_disp="—"
    local latest_active
    latest_active=$(ls -t "$agent_dir/results/"*.status.json 2>/dev/null | while IFS= read -r sf; do
      local s; s=$(jq -r '.status // ""' "$sf" 2>/dev/null)
      if [[ "$s" == "queued" || "$s" == "running" ]]; then echo "$sf"; break; fi
    done)
    if [[ -n "$latest_active" ]]; then
      task_disp=$(jq -r '.task_text // "—"' "$latest_active" 2>/dev/null)
      [[ -z "$task_disp" || "$task_disp" == "null" ]] && task_disp="—"
      [[ ${#task_disp} -gt 22 ]] && task_disp="${task_disp:0:19}..."
    fi

    printf "  %-16s %-12s ${status_color}%-10s${NC} %-8s %-6s %-24s %s\n" \
      "$display_name" "$runtime" "$status_text" "$pid_text" "$inbox_count" "$task_disp" "$last_active"
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
  local then_chain="" retry_max=0 strict=false dry_run=false
  local attach_files="" task_tags="" on_fail_cmd="" on_done_cmd="" task_timeout="" custom_id="" output_file="" task_env_vars="" notify=false broadcast_all=false broadcast_failed=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f)    force=true; shift ;;
      --headless)    headless=true; shift ;;
      --json)        json_output=true; shift ;;
      --no-context)  no_context=true; shift ;;
      --then)        then_chain="${then_chain:+$then_chain }$2"; shift 2 ;;
      --on-fail)     on_fail_cmd="$2"; shift 2 ;;
      --on-done)     on_done_cmd="$2"; shift 2 ;;
      --retry)       retry_max="$2"; shift 2 ;;
      --strict)      strict=true; shift ;;
      --dry-run)     dry_run=true; shift ;;
      --attach)      attach_files="${attach_files:+$attach_files$'\n'}$2"; shift 2 ;;
      --tag)         task_tags="${task_tags:+$task_tags$'\n'}$2"; shift 2 ;;
      --timeout)     task_timeout="$2"; shift 2 ;;
      --id)          custom_id="$2"; shift 2 ;;
      --output-file) output_file="$2"; shift 2 ;;
      --env)         [[ "$2" == *=* ]] || die "invalid --env format '$2' — use KEY=VAL"; task_env_vars="${task_env_vars:+$task_env_vars$'\n'}$2"; shift 2 ;;
      --notify)      notify=true; shift ;;
      --all)         broadcast_all=true; shift ;;
      --failed)      broadcast_failed=true; broadcast_all=true; shift ;;
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

  # Read from stdin if piped and no message given
  if [[ -z "$message" && ! -t 0 ]]; then
    message=$(cat)
  fi

  # --all broadcast mode
  if $broadcast_all; then
    [[ "$headless" == true ]] || die "--all requires --headless (broadcast is async)"
    [[ -z "$then_chain" ]] || die "--all cannot be combined with --then"
    # In --all mode, first positional is the message (no agent name)
    if [[ -z "$message" && -n "$to" ]]; then
      message="$to"; to=""
    fi
    [[ -n "$message" ]] || die "usage: sage send --all --headless <message>"
    local sent=0
    for d in "$AGENTS_DIR"/*/; do
      local n
      n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      agent_pid "$n" >/dev/null 2>&1 || continue
      if $broadcast_failed; then
        local _latest_status="" _latest_ts=0
        for _sf in "$d"results/*.status.json; do
          [[ -f "$_sf" ]] || continue
          local _ts; _ts=$(jq -r '.finished_at // .queued_at // 0' "$_sf" 2>/dev/null)
          [[ -z "$_ts" || "$_ts" == "null" ]] && _ts=0
          if [[ "$_ts" -gt "$_latest_ts" ]]; then
            _latest_ts="$_ts"; _latest_status="$_sf"
          fi
        done
        [[ -z "$_latest_status" ]] && continue
        local _rc; _rc=$(jq -r '.exit_code // 0' "$_latest_status" 2>/dev/null)
        [[ "$_rc" == "0" ]] && continue
      fi
      info "sending to $n"
      local send_args=("$n" "$message" --headless)
      $json_output && send_args+=(--json)
      cmd_send "${send_args[@]}" &
      sent=$((sent + 1))
    done
    if [[ $sent -eq 0 ]]; then
      if $broadcast_failed; then
        warn "no failed agents to retry"
      else
        warn "no running agents to broadcast to"
      fi
      return 0
    fi
    wait
    ok "broadcast sent to $sent agent(s)"
    return 0
  fi

  [[ -n "$to" && -n "$message" ]] || die "usage: sage send <agent> <message|@file|-> [--force|--headless|--json|--then <agent>]
  Reads from stdin when piped: echo 'msg' | sage send <agent> --headless"

  # --then requires --headless
  if [[ -n "$then_chain" && "$headless" != true ]]; then
    die "--then requires --headless (chaining needs synchronous execution)"
  fi
  # --on-fail requires --headless
  if [[ -n "$on_fail_cmd" && "$headless" != true ]]; then
    die "--on-fail requires --headless (callback needs synchronous execution)"
  fi
  # --on-done requires --headless
  if [[ -n "$on_done_cmd" && "$headless" != true ]]; then
    die "--on-done requires --headless (callback needs synchronous execution)"
  fi
  if [[ "$retry_max" -gt 0 && "$headless" != true ]]; then
    die "--retry requires --headless"
  fi
  if [[ "$strict" == true && "$headless" != true ]]; then
    die "--strict requires --headless"
  fi
  # --timeout requires --headless
  local _timeout_seconds=""
  if [[ -n "$task_timeout" ]]; then
    [[ "$headless" == true ]] || die "--timeout requires --headless"
    case "$task_timeout" in
      *m) _timeout_seconds=$(( ${task_timeout%m} * 60 )) ;;
      *h) _timeout_seconds=$(( ${task_timeout%h} * 3600 )) ;;
      *s) _timeout_seconds="${task_timeout%s}" ;;
      *[0-9]) _timeout_seconds="$task_timeout" ;;
      *)  die "invalid timeout '$task_timeout' — use Nm, Nh, Ns, or bare seconds" ;;
    esac
    [[ "$_timeout_seconds" =~ ^[0-9]+$ ]] || die "invalid timeout '$task_timeout'"
  fi
  # Validate --id
  if [[ -n "$custom_id" ]]; then
    [[ ${#custom_id} -le 64 ]] || die "invalid --id: max 64 characters"
    [[ "$custom_id" =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid --id '$custom_id': only alphanumeric, hyphens, underscores allowed"
  fi
  # --output-file requires --headless
  if [[ -n "$output_file" && "$headless" != true ]]; then
    die "--output-file requires --headless"
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
    if [[ "$headless" != true && "$dry_run" != true ]] && ! agent_pid "$to" >/dev/null 2>&1; then
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

  # Process --attach files: validate and append contents to message
  if [[ -n "$attach_files" ]]; then
    while IFS= read -r _af; do
      [[ -n "$_af" ]] || continue
      _af="${_af/#\~/$HOME}"
      [[ -f "$_af" ]] || die "attached file not found: $_af"
      local _sz
      _sz=$(wc -c < "$_af")
      [[ $_sz -le 102400 ]] || die "attached file too large (${_sz}B > 100KB): $_af"
      message="$message

--- $(basename "$_af") ---
$(cat "$_af")
--- end ---"
    done <<< "$attach_files"
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

  # Auto-inject per-agent memory
  local _mem_dir="$AGENTS_DIR/$to/memory"
  if [[ -d "$_mem_dir" ]]; then
    local _mem_keys _mem_block=""
    _mem_keys=$(ls "$_mem_dir/" 2>/dev/null) || true
    if [[ -n "$_mem_keys" ]]; then
      while IFS= read -r _mk; do
        _mem_block="${_mem_block}${_mk}=$(cat "$_mem_dir/$_mk")"$'\n'
      done <<< "$_mem_keys"
      message="[Memory]
${_mem_block}
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

  # --dry-run: print assembled prompt and exit
  if [[ "$dry_run" == true ]]; then
    printf '%s\n' "$message"
    return 0
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

    # Inject ad-hoc --env vars (per-task, not persisted)
    if [[ -n "$task_env_vars" ]]; then
      while IFS= read -r _tev || [[ -n "$_tev" ]]; do
        # shellcheck disable=SC2163
        [[ -n "$_tev" ]] && export "$_tev"
      done <<< "$task_env_vars"
    fi

    # Source tools and runtime
    for tool in "$SAGE_HOME/tools"/*.sh; do [[ -f "$tool" ]] && source "$tool"; done
    source "$SAGE_HOME/runtimes/${runtime}.sh"
    runtime_start "$agent_dir" "$to"

    local msg task_id start_ts rc=0
    task_id="${custom_id:-headless-$(date +%s)}"
    if [[ -n "$custom_id" && -f "$agent_dir/results/${task_id}.status.json" ]]; then
      die "task ID '$custom_id' already exists — use a unique --id"
    fi
    msg=$(jq -n --arg id "$task_id" --arg from "cli" --arg t "$message" '{id:$id,from:$from,payload:{text:$t}}')
    start_ts=$(date +%s)

    local task_output
    if [[ -n "$_timeout_seconds" ]]; then
      task_output=$( (runtime_inject "$to" "$msg" 2>&1) & _tpid=$!; (sleep "$_timeout_seconds"; kill $_tpid 2>/dev/null) & _wpid=$!; wait $_tpid 2>/dev/null; _trc=$?; kill $_wpid 2>/dev/null; wait $_wpid 2>/dev/null; exit $_trc ) || rc=$?
      # If killed by our timer, normalize to 124
      if [[ $rc -ne 0 && $rc -ne 124 ]]; then
        # Check if it was our kill (143=SIGTERM)
        [[ $rc -eq 143 || $rc -gt 128 ]] && rc=124
      fi
    else
      task_output=$(runtime_inject "$to" "$msg" 2>&1) || rc=$?
    fi

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

    # Strict mode: retry if output looks incomplete
    if [[ "$strict" == true && $rc -eq 0 ]]; then
      local _strict_i=0 _strict_max=3
      while [[ $_strict_i -lt $_strict_max ]]; do
        # Check for incompleteness markers (case-insensitive)
        local _lower
        _lower=$(printf '%s' "$task_output" | tr '[:upper:]' '[:lower:]')
        local _incomplete=false
        case "$_lower" in
          *"todo"*|*"fixme"*|*"i will "*|*"i cannot "*|*"i could not "*|*"i can't "*|*"i'll "*) _incomplete=true ;;
        esac
        if [[ "$_incomplete" != true ]]; then break; fi
        _strict_i=$((_strict_i + 1))
        log "strict: incomplete output detected, retry $_strict_i/$_strict_max"
        local _strict_msg
        _strict_msg=$(jq -n --arg id "$task_id" --arg from "cli" --arg t "STRICT MODE: Your previous response was incomplete. Complete the original task fully. Original task: $message" '{id:$id,from:$from,payload:{text:$t}}')
        rc=0
        task_output=$(runtime_inject "$to" "$_strict_msg" 2>&1) || rc=$?
      done
      # If still incomplete after all retries, exit 2
      if [[ $_strict_i -ge $_strict_max ]]; then
        local _lower_final
        _lower_final=$(printf '%s' "$task_output" | tr '[:upper:]' '[:lower:]')
        case "$_lower_final" in
          *"todo"*|*"fixme"*|*"i will "*|*"i cannot "*|*"i could not "*|*"i can't "*|*"i'll "*) rc=2 ;;
        esac
      fi
    fi

    # Write result files so `sage result <task_id>` works
    local _rstatus="done"; [[ $rc -ne 0 ]] && _rstatus="failed"
    local results_dir="$agent_dir/results"; mkdir -p "$results_dir"
    local _htags="[]"
    if [[ -n "$task_tags" ]]; then
      while IFS= read -r _t; do
        [[ -n "$_t" ]] || continue
        _htags=$(echo "$_htags" | jq --arg t "$_t" '. + [$t]')
      done <<< "$task_tags"
    fi
    jq -n --arg s "$_rstatus" --arg id "$task_id" --argjson rc "$rc" --argjson tags "$_htags" \
      '{id:$id,status:$s,exit_code:$rc,tags:$tags}' > "$results_dir/${task_id}.status.json"
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

    # Run failure callback if --on-fail specified and task failed
    if [[ -n "$on_fail_cmd" && "$_rstatus" != "done" ]]; then
      SAGE_FAIL_AGENT="$to" SAGE_FAIL_TASK="$task_id" SAGE_FAIL_OUTPUT="$task_output" \
        eval "$on_fail_cmd" || true
    fi

    # Run completion callback if --on-done specified (fires on success AND failure)
    if [[ -n "$on_done_cmd" ]]; then
      SAGE_DONE_AGENT="$to" SAGE_DONE_TASK="$task_id" SAGE_DONE_STATUS="$_rstatus" SAGE_DONE_OUTPUT="$task_output" \
        eval "$on_done_cmd" || true
    fi

    if [[ -n "$output_file" ]]; then
      mkdir -p "$(dirname "$output_file")"
      if [[ "$json_output" == true ]]; then
        jq -n --arg s "$_rstatus" --arg id "$task_id" --argjson rc "$rc" --argjson el "$elapsed" --arg out "$task_output" \
          '{status:$s,task_id:$id,exit_code:$rc,elapsed:$el,output:$out}' > "$output_file"
      else
        printf '%s\n' "$task_output" > "$output_file"
      fi
    elif [[ "$json_output" == true ]]; then
      jq -n --arg s "$_rstatus" --arg id "$task_id" --argjson rc "$rc" --argjson el "$elapsed" --arg out "$task_output" \
        '{status:$s,task_id:$id,exit_code:$rc,elapsed:$el,output:$out}'
    else
      [[ -n "$task_output" ]] && printf '%s\n' "$task_output"
    fi
    [[ "$notify" == true ]] && printf '\a'
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
  _SAGE_TASK_TAGS="$task_tags" task_id=$(send_msg "$to" "$payload")
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
# sage logs <name> [-f] [--clear] | sage logs --all [-f]
# ═══════════════════════════════════════════════
_filter_since() {
  local cutoff="$1"
  awk -v cutoff="$cutoff" '{
    if (match($0, /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]/)) {
      ts = substr($0, 2, 19)
      if (ts >= cutoff) print
    } else print
  }'
}

cmd_logs() {
  local name="" flag="" grep_pat="" all=false follow=false tail_n=50 since_secs=0 failed_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --grep) grep_pat="${2:-}"; [[ -n "$grep_pat" ]] || die "usage: sage logs <name> --grep <pattern>"; shift 2 ;;
      --tail) tail_n="${2:-}"; [[ "$tail_n" =~ ^[0-9]+$ ]] || die "--tail requires a number"; shift 2 ;;
      --since) since_secs=$(_parse_duration "${2:-}") || die "invalid duration '${2:-}' (use: 30m, 2h, 1d, 1w)"; shift 2 ;;
      --all) all=true; shift ;;
      --failed) failed_only=true; shift ;;
      -f) follow=true; shift ;;
      --clear) flag="--clear"; shift ;;
      -*) die "unknown flag: $1" ;;
      *) [[ -z "$name" ]] && name="$1" || true; shift ;;
    esac
  done
  [[ -n "$name" || "$all" == true || "$failed_only" == true ]] || die "usage: sage logs <name> [-f|--clear|--all|--failed|--grep <pattern>|--tail <N>|--since <duration>]"
  ensure_init

  if [[ "$failed_only" == true ]]; then
    _logs_failed "$tail_n"
    return
  fi

  if [[ "$all" == true ]]; then
    _logs_all "$($follow && echo "-f" || true)" "$grep_pat" "$tail_n" "$since_secs"
    return
  fi

  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid agent name"
  local logfile="$LOGS_DIR/$name.log"

  if [[ "$flag" == "--clear" ]]; then
    > "$logfile" 2>/dev/null
    ok "cleared logs for $name"
    return
  fi

  [[ -f "$logfile" ]] || die "no logs for '$name'"

  if [[ "$follow" == true ]]; then
    # Show existing matches first, then follow with filters
    local _cutoff=""
    if [[ "$since_secs" -gt 0 ]]; then
      _cutoff=$(date -d "@$(($(date +%s) - since_secs))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$(($(date +%s) - since_secs))" '+%Y-%m-%d %H:%M:%S')
    fi
    if [[ -n "$_cutoff" && -n "$grep_pat" ]]; then
      _filter_since "$_cutoff" < "$logfile" | grep -i --color=always "$grep_pat" || true
      tail -n 0 -f "$logfile" | grep -i --line-buffered --color=always "$grep_pat"
    elif [[ -n "$_cutoff" ]]; then
      _filter_since "$_cutoff" < "$logfile"
      tail -n 0 -f "$logfile"
    elif [[ -n "$grep_pat" ]]; then
      grep -i --color=always "$grep_pat" "$logfile" || true
      tail -n 0 -f "$logfile" | grep -i --line-buffered --color=always "$grep_pat"
    else
      tail -f "$logfile"
    fi
  elif [[ "$since_secs" -gt 0 ]]; then
    local cutoff; cutoff=$(date -d "@$(($(date +%s) - since_secs))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$(($(date +%s) - since_secs))" '+%Y-%m-%d %H:%M:%S')
    if [[ -n "$grep_pat" ]]; then
      _filter_since "$cutoff" < "$logfile" | grep -i --color=always "$grep_pat" | tail -"$tail_n" || true
    else
      _filter_since "$cutoff" < "$logfile" | tail -"$tail_n"
    fi
  elif [[ -n "$grep_pat" ]]; then
    grep -i --color=always "$grep_pat" "$logfile" | tail -"$tail_n" || true
  else
    tail -"$tail_n" "$logfile"
  fi
}

_logs_failed() {
  local tail_n="${1:-50}" found=false
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local n; n=$(basename "$d")
    [[ "$n" == .* ]] && continue
    # Find most recent task status file for this agent
    local latest="" latest_ts=0
    for sf in "$d"results/*.status.json; do
      [[ -f "$sf" ]] || continue
      local ts; ts=$(jq -r '.finished_at // .queued_at // 0' "$sf" 2>/dev/null)
      [[ -z "$ts" || "$ts" == "null" ]] && ts=0
      if [[ "$ts" -gt "$latest_ts" ]]; then latest_ts="$ts"; latest="$sf"; fi
    done
    [[ -z "$latest" ]] && continue
    local rc; rc=$(jq -r '.exit_code // 0' "$latest" 2>/dev/null)
    [[ "$rc" == "0" ]] && continue
    local lf="$LOGS_DIR/$n.log"
    [[ -f "$lf" ]] || continue
    found=true
    printf "=== %s ===\n" "$n"
    tail -"$tail_n" "$lf"
    echo
  done
  $found || info "no failed agents with logs"
}

_logs_all() {
  local follow="${1:-}" grep_pat="${2:-}" tail_n="${3:-50}" since_secs="${4:-0}" colors=("31" "32" "33" "34" "35" "36") ci=0 found=false
  local pids=() cutoff=""
  if [[ "$since_secs" -gt 0 ]]; then
    cutoff=$(date -d "@$(($(date +%s) - since_secs))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$(($(date +%s) - since_secs))" '+%Y-%m-%d %H:%M:%S')
  fi
  for logfile in "$LOGS_DIR"/*.log; do
    [[ -f "$logfile" ]] || continue
    local agent
    agent="$(basename "$logfile" .log)"
    found=true
    local c="${colors[$((ci % ${#colors[@]}))]}"
    ci=$((ci + 1))
    if [[ -n "$cutoff" && -n "$grep_pat" ]]; then
      _filter_since "$cutoff" < "$logfile" | grep -i "$grep_pat" 2>/dev/null | tail -"$tail_n" | sed "s/^/\\x1b[${c}m[${agent}]\\x1b[0m /" || true
    elif [[ -n "$cutoff" ]]; then
      _filter_since "$cutoff" < "$logfile" | tail -"$tail_n" | sed "s/^/\\x1b[${c}m[${agent}]\\x1b[0m /"
    elif [[ -n "$grep_pat" ]]; then
      grep -i "$grep_pat" "$logfile" 2>/dev/null | tail -"$tail_n" | sed "s/^/\\x1b[${c}m[${agent}]\\x1b[0m /" || true
    elif [[ "$follow" == "-f" ]]; then
      tail -f "$logfile" | sed "s/^/\\x1b[${c}m[${agent}]\\x1b[0m /" &
      pids+=($!)
    else
      tail -"$tail_n" "$logfile" | sed "s/^/\\x1b[${c}m[${agent}]\\x1b[0m /"
    fi
  done
  $found || die "no agent logs found"
  if [[ ${#pids[@]} -gt 0 ]]; then
    trap 'kill "${pids[@]}" 2>/dev/null' EXIT INT TERM
    wait
  fi
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
  local long=false json=false filter="" rt_filter="" sort_field="" tree=false quiet=false failed_only=false count_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -q|--quiet) quiet=true; shift ;;
      -l|--long) long=true; shift ;;
      --json) json=true; shift ;;
      --tree) tree=true; shift ;;
      --running) filter="running"; shift ;;
      --stopped) filter="stopped"; shift ;;
      --failed) failed_only=true; shift ;;
      --count) count_only=true; shift ;;
      --runtime) rt_filter="$2"; shift 2 ;;
      --sort) sort_field="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  # Validate sort field
  if [[ -n "$sort_field" ]]; then
    case "$sort_field" in
      name|runtime|status|last_active) ;;
      *) die "invalid sort field '$sort_field' (available: name, runtime, status, last_active)" ;;
    esac
  fi

  # --tree is incompatible with --json, --long, --sort
  if $tree; then
    $json && die "--tree cannot be combined with --json"
    $long && die "--tree cannot be combined with -l/--long"
    [[ -n "$sort_field" ]] && die "--tree cannot be combined with --sort"
  fi

  # --quiet is incompatible with --json, --long, --tree
  if $quiet; then
    $json && die "-q cannot be combined with --json"
    $long && die "-q cannot be combined with -l/--long"
    $tree && die "-q cannot be combined with --tree"
  fi

  # Collect agent data: name\truntime\tmodel\tstatus\tlast_active
  local _ls_lines=""
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local n=$(basename "$d")
    [[ "$n" == .* ]] && continue
    local rt=$(jq -r '.runtime // "bash"' "$d/runtime.json" 2>/dev/null || echo "bash")
    local md=$(jq -r '.model // "default"' "$d/runtime.json" 2>/dev/null || echo "default")
    [[ -z "$md" ]] && md="default"
    local st="stopped"
    agent_pid "$n" >/dev/null 2>&1 && st="running"
    [[ -n "$filter" && "$filter" != "$st" ]] && continue
    [[ -n "$rt_filter" && "$rt" != "$rt_filter" ]] && continue
    # --failed: only show agents whose most recent task exited non-zero
    if $failed_only; then
      # Find status file with highest finished_at/queued_at timestamp
      local _latest_status="" _latest_ts=0
      for _sf in "$d"results/*.status.json; do
        [[ -f "$_sf" ]] || continue
        local _ts=$(jq -r '.finished_at // .queued_at // 0' "$_sf" 2>/dev/null)
        [[ -z "$_ts" || "$_ts" == "null" ]] && _ts=0
        if [[ "$_ts" -gt "$_latest_ts" ]]; then
          _latest_ts="$_ts"; _latest_status="$_sf"
        fi
      done
      [[ -z "$_latest_status" ]] && continue
      local _rc=$(jq -r '.exit_code // 0' "$_latest_status" 2>/dev/null)
      [[ "$_rc" == "0" ]] && continue
    fi
    local la="never"
    if ls "$d"results/*.status.json >/dev/null 2>&1; then
      la=$(jq -r '.finished_at // .queued_at // empty' "$d"results/*.status.json 2>/dev/null | sort | tail -1)
      [[ -z "$la" ]] && la="never"
    fi
    _ls_lines="${_ls_lines}${n}	${rt}	${md}	${st}	${la}
"
  done

  # Sort if requested
  if [[ -n "$sort_field" && -n "$_ls_lines" ]]; then
    local _sk=1
    case "$sort_field" in
      name) _sk=1 ;; runtime) _sk=2 ;; status) _sk=4 ;; last_active) _sk=5 ;;
    esac
    _ls_lines=$(printf '%s' "$_ls_lines" | sort -t'	' -k"$_sk","$_sk")
  fi

  if $count_only; then
    local _cnt=0
    while IFS=$'\t' read -r n rt md st la; do
      [[ -n "$n" ]] || continue
      _cnt=$((_cnt + 1))
    done <<< "$_ls_lines"
    printf '%d\n' "$_cnt"
    return 0
  fi

  if $quiet; then
    while IFS='	' read -r n rt md st la; do
      [[ -n "$n" ]] || continue
      printf '%s\n' "$n"
    done <<< "$_ls_lines"
    return 0
  fi

  if $json; then
    local first=true
    printf '['
    while IFS='	' read -r n rt md st la; do
      [[ -n "$n" ]] || continue
      $first || printf ','
      first=false
      printf '{"name":"%s","runtime":"%s","model":"%s","status":"%s","last_active":"%s"}' "$n" "$rt" "$md" "$st" "$la"
    done <<< "$_ls_lines"
    printf ']\n'
    return 0
  fi

  if $long; then
    printf "%-16s %-12s %-14s %-10s %s\n" "NAME" "RUNTIME" "MODEL" "STATUS" "LAST_ACTIVE"
    while IFS='	' read -r n rt md st la; do
      [[ -n "$n" ]] || continue
      [[ "$la" != "never" ]] && la="${la%%T*}"
      printf "%-16s %-12s %-14s %-10s %s\n" "$n" "$rt" "$md" "$st" "$la"
    done <<< "$_ls_lines"
    return 0
  fi

  if $tree; then
    # Build list of agent names that passed filters
    local _tree_names=""
    while IFS='	' read -r n _rest; do
      [[ -n "$n" ]] || continue
      _tree_names="$_tree_names $n"
    done <<< "$_ls_lines"
    # Print tree: roots first, then children
    _print_tree() {
      local parent="$1" prefix="$2"
      local children=""
      for n in $_tree_names; do
        local p=$(jq -r '.parent // ""' "$AGENTS_DIR/$n/runtime.json" 2>/dev/null)
        [[ "$p" == "$parent" ]] && children="$children $n"
      done
      local count=0 total=0
      for _ in $children; do total=$((total+1)); done
      for c in $children; do
        count=$((count+1))
        if [[ $count -eq $total ]]; then
          echo "${prefix}└── $c"
          _print_tree "$c" "${prefix}    "
        else
          echo "${prefix}├── $c"
          _print_tree "$c" "${prefix}│   "
        fi
      done
    }
    # Print root agents (no parent or parent not in list)
    for n in $_tree_names; do
      local p=$(jq -r '.parent // ""' "$AGENTS_DIR/$n/runtime.json" 2>/dev/null)
      if [[ -z "$p" ]] || ! echo "$_tree_names" | grep -qw "$p"; then
        echo "$n"
        _print_tree "$n" ""
      fi
    done
    return 0
  fi

  while IFS='	' read -r n _rest; do
    [[ -n "$n" ]] || continue
    echo "$n"
  done <<< "$_ls_lines"
}

# ═══════════════════════════════════════════════
# sage rm <name>
# ═══════════════════════════════════════════════
cmd_rm() {
  local name="" stopped=false failed_only=false dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stopped) stopped=true; shift ;;
      --failed)  failed_only=true; shift ;;
      --dry-run) dry_run=true; shift ;;
      --force) shift ;;  # accepted for compat, no-op
      -*) die "usage: sage rm <name> | sage rm --stopped [--dry-run] | sage rm --failed [--dry-run]" ;;
      *) name="$1"; shift ;;
    esac
  done
  ensure_init
  if $stopped || $failed_only; then
    [[ -z "$name" ]] || die "--stopped/--failed cannot be combined with a name"
    local count=0 label="stopped"
    $failed_only && label="failed"
    for d in "$AGENTS_DIR"/*/runtime.json; do
      [[ -f "$d" ]] || continue
      local aname
      aname=$(basename "$(dirname "$d")")
      agent_pid "$aname" >/dev/null 2>&1 && continue
      if $failed_only; then
        # latest status file (by finished_at/queued_at) must have non-zero exit_code
        local _latest_status="" _latest_ts=0
        for _sf in "$AGENTS_DIR/$aname"/results/*.status.json; do
          [[ -f "$_sf" ]] || continue
          local _ts; _ts=$(jq -r '.finished_at // .queued_at // 0' "$_sf" 2>/dev/null)
          [[ -z "$_ts" || "$_ts" == "null" ]] && _ts=0
          if [[ "$_ts" -gt "$_latest_ts" ]]; then _latest_ts="$_ts"; _latest_status="$_sf"; fi
        done
        [[ -z "$_latest_status" ]] && continue
        local _rc; _rc=$(jq -r '.exit_code // 0' "$_latest_status" 2>/dev/null)
        [[ "$_rc" == "0" ]] && continue
      fi
      if $dry_run; then echo "  would remove: $aname"
      else
        local agent_dir="$AGENTS_DIR/$aname"
        if [[ "$(jq -r '.worktree // false' "$agent_dir/runtime.json" 2>/dev/null)" == "true" ]]; then
          git worktree remove "$agent_dir/workspace" --force 2>/dev/null || true
        fi
        rm -rf "$agent_dir"
        rm -f "$LOGS_DIR/$aname.log"
        echo "  removed: $aname"
      fi
      count=$((count + 1))
    done
    if $dry_run; then ok "dry-run: $count $label agent(s) would be removed"
    else ok "removed $count $label agent(s)"; fi
    return 0
  fi
  [[ -n "$name" ]] || die "usage: sage rm <name> | sage rm --stopped [--dry-run] | sage rm --failed [--dry-run]"
  agent_exists "$name"
  stop_agent "$name" 2>/dev/null || true
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
  local dry_run=false count=0
  [[ "${1:-}" == "--dry-run" ]] && dry_run=true
  # Stale pid files
  while IFS= read -r -d '' pidfile; do
    local pid_val
    pid_val=$(cat "$pidfile" 2>/dev/null)
    if [[ "$pid_val" =~ ^[0-9]+$ ]] && ! kill -0 "$pid_val" 2>/dev/null; then
      if $dry_run; then echo "  would remove stale pid: $pidfile"; else rm -f "$pidfile"; fi
      count=$((count + 1))
    fi
  done < <(find "$AGENTS_DIR" -name ".pid" -print0 2>/dev/null)
  # Old temp files
  while IFS= read -r f; do
    if $dry_run; then echo "  would remove temp: $f"; else rm -f "$f"; fi
    count=$((count + 1))
  done < <(find /tmp -name "sage-*" -type f -mmin +60 2>/dev/null || true)
  # Old reply files
  while IFS= read -r f; do
    if $dry_run; then echo "  would remove reply: $f"; else rm -f "$f"; fi
    count=$((count + 1))
  done < <(find "$AGENTS_DIR" -path "*/replies/*.json" -mmin +60 2>/dev/null || true)
  if $dry_run; then ok "dry-run: $count file(s) would be cleaned"
  else ok "cleaned $count stale file(s)"; fi
}

# ═══════════════════════════════════════════════
# sage wait <name|--all> [--timeout <sec>]
# ═══════════════════════════════════════════════
cmd_wait() {
  local name="" timeout=0 poll_interval=5 all_mode=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)        all_mode=true; shift ;;
      --timeout|-t) timeout="$2"; shift 2 ;;
      -*)           die "unknown flag: $1" ;;
      *)            name="$1"; shift ;;
    esac
  done

  ensure_init

  if $all_mode; then
    [[ -n "$name" ]] && die "--all cannot be combined with an agent name"
    # Collect running agents
    local running=()
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n; n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      agent_pid "$n" >/dev/null 2>&1 && running+=("$n")
    done
    if [[ ${#running[@]} -eq 0 ]]; then
      ok "no running agents"
      return 0
    fi
    info "waiting for ${#running[@]} agent(s): ${running[*]}"
    [[ $timeout -gt 0 ]] && info "timeout: ${timeout}s"
    local start_time=$SECONDS
    while [[ ${#running[@]} -gt 0 ]]; do
      local still=()
      for n in "${running[@]}"; do
        if agent_pid "$n" >/dev/null 2>&1; then
          still+=("$n")
        else
          ok "$n completed"
        fi
      done
      running=("${still[@]+"${still[@]}"}")
      [[ ${#running[@]} -eq 0 ]] && break
      if [[ $timeout -gt 0 && $((SECONDS - start_time)) -ge $timeout ]]; then
        warn "timeout after ${timeout}s — still running: ${running[*]}"
        return 124
      fi
      sleep "$poll_interval"
    done
    ok "all agents completed"
    return 0
  fi

  [[ -n "$name" ]] || die "usage: sage wait <name|--all> [--timeout <sec>]"
  agent_exists "$name"

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
# sage watch <dir> --agent <name> [--pattern GLOB] [--debounce N] [--max-triggers N]
# ═══════════════════════════════════════════════
cmd_watch() {
  local dir="" agent="" pattern="" debounce=2 max_triggers=0 task_msg="" on_change="" plan_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent|-a)       agent="$2"; shift 2 ;;
      --pattern|-p)     pattern="$2"; shift 2 ;;
      --debounce|-d)    debounce="$2"; shift 2 ;;
      --max-triggers)   max_triggers="$2"; shift 2 ;;
      --task|-t)        task_msg="$2"; shift 2 ;;
      --on-change)      on_change="$2"; shift 2 ;;
      --plan)           plan_file="$2"; shift 2 ;;
      --help|-h)
        cat <<'HELP'
Usage: sage watch <dir> [--agent <name>] [--on-change <cmd>] [--plan <file>] [options]

Watch a directory for file changes and trigger an agent, command, or plan.

Options:
  --agent, -a <name>    Agent to trigger on change
  --on-change <cmd>     Run command on change (SAGE_WATCH_FILES env set)
  --plan <file>         Re-run a plan YAML on change
  --pattern, -p <glob>  Filter files by glob (e.g. '*.py')
  --debounce, -d <sec>  Cooldown between triggers (default: 2)
  --max-triggers <n>    Exit after N triggers (0 = unlimited)
  --task, -t <msg>      Custom task message (default: auto-generated)
  --help, -h            Show this help

Requires --agent, --on-change, or --plan (mutually exclusive).
HELP
        return 0 ;;
      -*) die "unknown flag: $1" ;;
      *)  dir="$1"; shift ;;
    esac
  done

  [[ -n "$dir" ]] || die "usage: sage watch <dir> --agent <name> [--pattern GLOB]"
  [[ -n "$agent" || -n "$on_change" || -n "$plan_file" ]] || die "requires --agent, --on-change, or --plan"
  local _mode_count=0
  [[ -n "$agent" ]] && _mode_count=$((_mode_count + 1))
  [[ -n "$on_change" ]] && _mode_count=$((_mode_count + 1))
  [[ -n "$plan_file" ]] && _mode_count=$((_mode_count + 1))
  [[ "$_mode_count" -le 1 ]] || die "--agent, --on-change, and --plan are mutually exclusive"
  [[ -d "$dir" ]] || die "directory does not exist: $dir"
  if [[ -n "$plan_file" && ! -f "$plan_file" ]]; then
    die "plan file not found: $plan_file"
  fi
  if [[ -n "$agent" ]]; then
    ensure_init; agent_exists "$agent"
  fi

  local trigger_count=0
  local snapshot_file
  snapshot_file=$(mktemp)
  trap 'rm -f "${snapshot_file:-}"' EXIT

  # Take initial snapshot: file paths + mtimes
  _watch_snapshot() {
    if [[ -n "$pattern" ]]; then
      find "$dir" -name "$pattern" -type f -exec stat -c '%n %Y' {} + 2>/dev/null | sort
    else
      find "$dir" -type f -exec stat -c '%n %Y' {} + 2>/dev/null | sort
    fi
  }

  # macOS compat: stat format differs
  if ! stat -c '%n' /dev/null >/dev/null 2>&1; then
    _watch_snapshot() {
      if [[ -n "$pattern" ]]; then
        find "$dir" -name "$pattern" -type f -exec stat -f '%N %m' {} + 2>/dev/null | sort
      else
        find "$dir" -type f -exec stat -f '%N %m' {} + 2>/dev/null | sort
      fi
    }
  fi

  _watch_snapshot > "$snapshot_file"
  info "watching $dir for changes (agent: $agent, debounce: ${debounce}s)"
  [[ -n "$pattern" ]] && info "pattern: $pattern"
  info "press Ctrl-C to stop"

  while true; do
    sleep 1
    local new_snapshot_file
    new_snapshot_file=$(mktemp)
    _watch_snapshot > "$new_snapshot_file"
    local changed
    changed=$(diff "$snapshot_file" "$new_snapshot_file" 2>/dev/null | grep '^>' | sed 's/^> //' | awk '{print $1}' || true)

    if [[ -n "$changed" ]]; then
      local file_list
      file_list=$(echo "$changed" | head -5)
      local count
      count=$(echo "$changed" | wc -l | tr -d ' ')
      cp "$new_snapshot_file" "$snapshot_file"
      rm -f "$new_snapshot_file"

      info "change detected: $count file(s)"
      echo "$file_list" | while IFS= read -r f; do
        [[ -n "$f" ]] && echo "  $f"
      done

      # Debounce
      [[ "$debounce" -gt 0 ]] && sleep "$debounce"

      # Re-snapshot after debounce to catch rapid saves
      _watch_snapshot > "$snapshot_file"

      local msg="${task_msg:-Files changed in $dir: $file_list}"
      if [[ -n "$on_change" ]]; then
        info "running: $on_change"
        SAGE_WATCH_FILES="$changed" eval "$on_change" || warn "on-change command failed"
      elif [[ -n "$plan_file" ]]; then
        info "running plan: $plan_file"
        SAGE_WATCH_FILES="$changed" cmd_plan --run "$plan_file" --yes 2>/dev/null || warn "plan execution failed"
      else
        info "triggering $agent..."
        cmd_send "$agent" "$msg" 2>/dev/null || warn "failed to send to $agent"
      fi

      trigger_count=$((trigger_count + 1))
      if [[ "$max_triggers" -gt 0 && "$trigger_count" -ge "$max_triggers" ]]; then
        info "reached max triggers ($max_triggers), exiting"
        rm -f "$new_snapshot_file"
        return 0
      fi
    else
      rm -f "$new_snapshot_file"
    fi
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
  local name="" json_mode=false status_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --status) status_filter="${2:-}"; [[ -n "$status_filter" ]] || die "usage: sage tasks --status <done|failed|running|queued>"
               case "$status_filter" in done|failed|running|queued) ;; *) die "invalid status '$status_filter' (use: done, failed, running, queued)" ;; esac
               shift 2 ;;
      -*) die "usage: sage tasks [name] [--json] [--status <done|failed|running|queued>]" ;;
      *) name="$1"; shift ;;
    esac
  done
  ensure_init
  set +e

  local now=$(date +%s)
  local found=0 json_arr="["

  $json_mode || printf "\n${BOLD}  ⚡ Tasks${NC}\n\n"
  $json_mode || printf "  ${DIM}%-20s %-12s %-10s %-10s %s${NC}\n" "TASK" "AGENT" "STATUS" "ELAPSED" "FROM"

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

      local task_id=$(jq -r '.id' "$status_file")
      local status=$(jq -r '.status' "$status_file")
      [[ -n "$status_filter" && "$status" != "$status_filter" ]] && continue
      local from=$(jq -r '.from' "$status_file")
      local queued_at=$(jq -r '.queued_at // 0' "$status_file")
      local finished_at=$(jq -r '.finished_at // 0' "$status_file")
      local task_text=$(jq -r '.task_text // ""' "$status_file")

      local elapsed_secs
      if [[ "$finished_at" != "null" && "$finished_at" != "0" ]]; then
        elapsed_secs=$(( finished_at - queued_at ))
      else
        elapsed_secs=$(( now - queued_at ))
      fi
      ((found++)) || true

      if $json_mode; then
        [[ "$found" -gt 1 ]] && json_arr="$json_arr,"
        json_arr="$json_arr$(jq -nc --arg i "$task_id" --arg a "$agent_name" --arg s "$status" \
          --argjson e "$elapsed_secs" --arg f "$from" --arg t "$task_text" \
          '{id:$i,agent:$a,status:$s,elapsed_secs:$e,from:$f,task_text:$t}')"
      else
        local status_color
        case "$status" in
          done)    status_color="$GREEN" ;;
          running) status_color="$YELLOW" ;;
          queued)  status_color="$DIM" ;;
          failed)  status_color="$RED" ;;
          *)       status_color="$NC" ;;
        esac
        printf "  %-20s %-12s ${status_color}%-10s${NC} %-10s %s\n" \
          "$task_id" "$agent_name" "$status" "${elapsed_secs}s" "$from"
      fi
    done
  done

  if $json_mode; then
    printf '%s]\n' "$json_arr"
  else
    [[ $found -eq 0 ]] && printf "  ${DIM}no tasks${NC}\n"
    printf "\n"
  fi
}

# ═══════════════════════════════════════════════
# sage result <task-id>
# ═══════════════════════════════════════════════
cmd_result() {
  local task_id="" agent_filter="" all_mode=false json_output=false failed_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)    all_mode=true; shift ;;
      --failed) failed_only=true; all_mode=true; shift ;;
      --json)   json_output=true; shift ;;
      --agent)  agent_filter="${2:-}"; [[ -n "$agent_filter" ]] || die "usage: sage result [task-id] [--agent <name>]"; shift 2 ;;
      -*)       die "usage: sage result [task-id] [--agent <name>]" ;;
      *)        task_id="$1"; shift ;;
    esac
  done
  ensure_init

  if $all_mode; then
    [[ -z "$task_id" ]] || die "--all cannot be combined with a task-id"
    local json_arr="[" first=true found=0
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n; n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      local newest="" newest_time=0
      for f in "$d"/results/*.status.json; do
        [[ -f "$f" ]] || continue
        local mt; mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || continue
        [[ "$mt" -gt "$newest_time" ]] && { newest_time=$mt; newest=$f; }
      done
      [[ -n "$newest" ]] || continue
      # --failed: skip agents whose latest task succeeded (exit_code == 0)
      if $failed_only; then
        local _rc; _rc=$(jq -r '.exit_code // 0' "$newest" 2>/dev/null)
        [[ "$_rc" == "0" ]] && continue
      fi
      found=$((found + 1))
      local tid; tid=$(basename "$newest" .status.json)
      local st; st=$(jq -r '.status' "$newest")
      local rf="$d/results/${tid}.result.json"
      local out=""
      [[ -f "$rf" ]] && out=$(cat "$rf")
      if $json_output; then
        $first || json_arr+=","
        first=false
        json_arr+=$(jq -nc --arg a "$n" --arg s "$st" --arg t "$tid" --arg o "$out" '{agent:$a,status:$s,task_id:$t,output:$o}')
      else
        printf "=== %s (task: %s, status: %s) ===\n" "$n" "$tid" "$st"
        [[ -n "$out" ]] && echo "$out" || echo "(no output)"
        echo
      fi
    done
    if $json_output; then echo "${json_arr}]"; else [[ $found -gt 0 ]] || info "no results found"; fi
    return 0
  fi

  [[ -n "$agent_filter" ]] && agent_exists "$agent_filter"

  # Build glob pattern based on agent filter
  local search_glob
  if [[ -n "$agent_filter" ]]; then
    search_glob="$AGENTS_DIR/$agent_filter/results/*.status.json"
  else
    search_glob="$AGENTS_DIR/*/results/*.status.json"
  fi

  # No task-id: find most recent task by file modification time
  if [[ -z "$task_id" ]]; then
    local newest="" newest_time=0
    for f in $search_glob; do
      [[ -f "$f" ]] || continue
      local mtime
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || continue
      if [[ "$mtime" -gt "$newest_time" ]]; then
        newest_time=$mtime
        newest=$f
      fi
    done
    [[ -n "$newest" ]] || die "No tasks found${agent_filter:+ for agent '$agent_filter'} — run a task first with sage send"
    task_id=$(basename "$newest" .status.json)
  fi

  # Search agents for this task
  local search_dirs
  if [[ -n "$agent_filter" ]]; then
    search_dirs="$AGENTS_DIR/$agent_filter/results"
  else
    search_dirs="$AGENTS_DIR/*/results"
  fi

  for results_dir in $search_dirs; do
    [[ -d "$results_dir" ]] || continue
    local status_file="$results_dir/${task_id}.status.json"
    local result_file="$results_dir/${task_id}.result.json"

    if [[ -f "$status_file" ]]; then
      local status=$(jq -r '.status' "$status_file")
      local agent_name=$(basename "$(dirname "$results_dir")")

      if [[ "$status" == "done" && -f "$result_file" ]]; then
        cat "$result_file"
      elif [[ "$status" == "done" ]]; then
        echo "{\"status\":\"done\",\"agent\":\"$agent_name\",\"note\":\"task completed — check sage logs $agent_name for output\"}"
      elif [[ "$status" == "running" ]]; then
        echo "{\"status\":\"running\",\"agent\":\"$agent_name\",\"hint\":\"use sage peek $agent_name to see progress\"}"
      else
        cat "$status_file"
      fi
      return 0
    fi
  done

  die "task '$task_id' not found${agent_filter:+ in agent '$agent_filter'}"
}

# ═══════════════════════════════════════════════
# sage replay [task-id] [--agent <name>] [--dry-run]
# ═══════════════════════════════════════════════
cmd_replay() {
  local task_id="" override_agent="" dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)   override_agent="$2"; shift 2 ;;
      --dry-run) dry_run=true; shift ;;
      -*)        die "unknown flag: $1" ;;
      *)         task_id="$1"; shift ;;
    esac
  done
  ensure_init

  # No task-id: find most recent by mtime
  if [[ -z "$task_id" ]]; then
    local newest="" newest_time=0
    for f in "$AGENTS_DIR"/*/results/*.status.json; do
      [[ -f "$f" ]] || continue
      local mtime
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || continue
      if [[ "$mtime" -gt "$newest_time" ]]; then
        newest_time=$mtime; newest=$f
      fi
    done
    [[ -n "$newest" ]] || die "No tasks found"
    task_id=$(basename "$newest" .status.json)
  fi

  # Find the status.json
  local found_file="" found_agent=""
  for results_dir in "$AGENTS_DIR"/*/results; do
    [[ -f "$results_dir/${task_id}.status.json" ]] || continue
    found_file="$results_dir/${task_id}.status.json"
    found_agent=$(basename "$(dirname "$results_dir")")
    break
  done
  [[ -n "$found_file" ]] || die "task '$task_id' not found"

  local task_text
  task_text=$(jq -r '.task_text // ""' "$found_file" 2>/dev/null)
  [[ -n "$task_text" && "$task_text" != "null" ]] || die "no task text stored for '$task_id'"

  local target="${override_agent:-$found_agent}"

  if [[ "$dry_run" == true ]]; then
    echo "replay → agent=$target task=$task_text"
    return 0
  fi

  info "replaying task to $target: $task_text"
  cmd_send "$target" "$task_text"
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
  local format="pretty" do_clear=false from_filter="" count_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)  format="json"; shift ;;
      --clear) do_clear=true; shift ;;
      --count) count_only=true; shift ;;
      --from)  from_filter="${2:-}"; [[ -n "$from_filter" ]] || die "usage: sage inbox --from <agent>"; shift 2 ;;
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

  if [[ "$count_only" == true ]]; then
    local n=0
    for msg_file in "$inbox"/*.json; do
      [[ -f "$msg_file" ]] || continue
      if [[ -n "$from_filter" ]]; then
        local _sender; _sender=$(jq -r '.from // ""' "$msg_file" 2>/dev/null)
        [[ "$_sender" == "$from_filter" ]] || continue
      fi
      ((n++)) || true
    done
    echo "$n"
    return
  fi

  local msg_count=0
  for msg_file in $(ls -t "$inbox"/*.json 2>/dev/null); do
    [[ -f "$msg_file" ]] || continue
    if [[ -n "$from_filter" ]]; then
      local _sender; _sender=$(jq -r '.from // ""' "$msg_file" 2>/dev/null)
      [[ "$_sender" == "$from_filter" ]] || continue
    fi
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
  local mode="timeline" limit=50 do_clear=false agent_filter="" json_out=false since_cutoff=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tree)  mode="tree"; shift ;;
      --json)  json_out=true; shift ;;
      --clear) do_clear=true; shift ;;
      --since) local _dur; _dur=$(_parse_duration "$2") || die "invalid duration '$2' (use: 30m, 2h, 1d, 1w)"
               since_cutoff=$(( $(date +%s) - _dur )); shift 2 ;;
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

  [[ -f "$tracefile" ]] || { if [[ "$json_out" == true ]]; then printf '[]\n'; else printf "\n  ${DIM}no trace data — run some tasks first${NC}\n\n"; fi; return; }

  # Filter trace to specific agent (matches from, to, or agent fields)
  local trace_data
  if [[ -n "$agent_filter" ]]; then
    trace_data=$(grep -E "\"(from|to|agent)\":\"$agent_filter\"" "$tracefile" | tail -"$limit")
  else
    trace_data=$(tail -"$limit" "$tracefile")
  fi

  [[ -n "$trace_data" ]] || { if [[ "$json_out" == true ]]; then printf '[]\n'; else printf "\n  ${DIM}no trace data for '$agent_filter'${NC}\n\n"; fi; return; }

  # Apply --since time filter
  if [[ "$since_cutoff" -gt 0 ]]; then
    trace_data=$(echo "$trace_data" | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ts; ts=$(echo "$line" | jq -r '.ts' 2>/dev/null) || continue
      [[ "$ts" -ge "$since_cutoff" ]] && printf '%s\n' "$line"
    done)
    [[ -n "$trace_data" ]] || { if [[ "$json_out" == true ]]; then printf '[]\n'; else printf "\n  ${DIM}no trace data in time window${NC}\n\n"; fi; return; }
  fi

  if [[ "$json_out" == true ]]; then
    printf '[%s]\n' "$(echo "$trace_data" | sed '/^$/d' | paste -sd ',' -)"
    return
  fi

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
    add) [[ -n "${2:-}" && -n "${3:-}" ]] || die "usage: sage tool add <name> <path> [--desc text]"
         local tname="$2" tpath="$3"; shift 3
         cp "$tpath" "$TOOLS_DIR/$tname.sh"; chmod +x "$TOOLS_DIR/$tname.sh"
         if [[ "${1:-}" == "--desc" ]]; then shift; echo "$*" > "$TOOLS_DIR/$tname.desc"; fi
         ok "tool '$tname' registered" ;;
    ls)  if [[ "${2:-}" == "--json" ]]; then
           printf '['
           local _first=true
           for t in "$TOOLS_DIR"/*.sh; do
             [[ -f "$t" ]] || continue
             local n; n=$(basename "$t" .sh)
             local d=""; [[ -f "$TOOLS_DIR/$n.desc" ]] && d=$(cat "$TOOLS_DIR/$n.desc")
             local _dj; _dj=$(printf '%s' "$d" | jq -Rs .)
             [[ "$_first" == true ]] && _first=false || printf ','
             printf '{"name":"%s","description":%s}' "$n" "$_dj"
           done
           printf ']\n'
           return
         fi
         for t in "$TOOLS_DIR"/*.sh; do
           [[ -f "$t" ]] || continue
           local n; n=$(basename "$t" .sh)
           local d=""; [[ -f "$TOOLS_DIR/$n.desc" ]] && d=$(cat "$TOOLS_DIR/$n.desc")
           if [[ -n "$d" ]]; then printf "%-20s %s\n" "$n" "$d"; else echo "$n"; fi
         done ;;
    rm)  [[ -n "${2:-}" ]] || die "usage: sage tool rm <name> [--dry-run]"
         [[ -f "$TOOLS_DIR/$2.sh" ]] || die "tool '$2' not found"
         if [[ "${3:-}" == "--dry-run" ]]; then
           echo "would remove tool '$2' at $TOOLS_DIR/$2.sh"
           [[ -f "$TOOLS_DIR/$2.desc" ]] && echo "  desc: $TOOLS_DIR/$2.desc"
           return 0
         fi
         rm -f "$TOOLS_DIR/$2.sh" "$TOOLS_DIR/$2.desc"; ok "tool '$2' removed" ;;
    show) [[ -n "${2:-}" ]] || die "usage: sage tool show <name>"
          [[ -f "$TOOLS_DIR/$2.sh" ]] || die "tool '$2' not found"
          cat "$TOOLS_DIR/$2.sh" ;;
    run)  [[ -n "${2:-}" ]] || die "usage: sage tool run <name> [args...]"
          [[ -f "$TOOLS_DIR/$2.sh" ]] || die "tool '$2' not found"
          local tool_name="$2"; shift 2
          bash "$TOOLS_DIR/$tool_name.sh" "$@" ;;
    *)   die "usage: sage tool {add|ls|rm|run|show}" ;;
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
  local run_id="" cycle_num="" show_active=false json_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --active|-a) show_active=true; shift ;;
      --json)      json_mode=true; shift ;;
      -c)          cycle_num="$2"; shift 2 ;;
      -*)          die "unknown flag: $1" ;;
      *)           run_id="$1"; shift ;;
    esac
  done

  ensure_init
  mkdir -p "$RUNS_DIR"

  if [[ -z "$run_id" ]]; then
    if [[ "$json_mode" == true ]]; then
      local _first=true
      printf '['
      for d in "$RUNS_DIR"/*/state.json; do
        [[ -f "$d" ]] || continue
        local st
        st=$(jq -r '.status' "$d")
        [[ "$show_active" == true && "$st" != "running" ]] && continue
        $_first || printf ','
        jq -c '{run_id, status, current_cycle, goal}' "$d"
        _first=false
      done
      printf ']\n'
      return 0
    fi
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
      --show)     [[ -n "${2:-}" ]] || die "usage: sage plan --show <plan-file>"; _plan_show "$2"; return 0 ;;
      --validate) [[ -n "${2:-}" ]] || die "usage: sage plan --validate <plan-file>"; _plan_validate "$2"; return $? ;;
      --recover)  _plan_recover "$auto_approve"; return $? ;;
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

  # Run from saved plan file (JSON) or pattern file (YAML)
  if [[ -n "$run_file" ]]; then
    [[ -f "$run_file" ]] || die "plan file not found: $run_file"
    if [[ "$run_file" == *.yaml || "$run_file" == *.yml ]]; then
      local y_pattern y_task y_inputs
      y_pattern=$(grep -E '^pattern:' "$run_file" | head -1 | sed 's/^pattern:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//' || true)
      y_task=$(grep -E '^task:' "$run_file" | head -1 | sed 's/^task:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//' || true)
      y_inputs=$(grep -E '^inputs:' "$run_file" | head -1 | sed 's/^inputs:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//' || true)
      # Handle YAML list syntax: [a, b, c] → a,b,c
      y_inputs=$(echo "$y_inputs" | sed 's/^\[//;s/\]$//;s/,[[:space:]]*/,/g')
      [[ -n "$y_pattern" ]] || die "YAML pattern file missing 'pattern:' field"
      _plan_pattern "$y_pattern" "$y_task" "$y_inputs" "$save_file" "$auto_approve"
      return $?
    fi
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
        desc=$(echo "$args" | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
        deps=$(echo "$args" | sed -n 's/.*--depends[[:space:]]*\([0-9,]*\).*/\1/p')
        [[ -z "$deps" ]] && deps=""

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
        local new_desc=$(echo "$args" | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
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

# Recover interrupted plans (status=running but no live agents)
_plan_recover() {
  local auto="${1:-false}"
  ensure_init
  mkdir -p "$PLANS_DIR"

  local interrupted=()
  for pf in "$PLANS_DIR"/*.json; do
    [[ -f "$pf" ]] || continue
    local st
    st=$(jq -r '.status // "unknown"' "$pf")
    [[ "$st" == "running" ]] && interrupted+=("$pf")
  done

  if [[ ${#interrupted[@]} -eq 0 ]]; then
    ok "no interrupted plans"
    return 0
  fi

  printf "\n${BOLD}  ⚡ %d interrupted plan(s)${NC}\n\n" "${#interrupted[@]}"
  for pf in "${interrupted[@]}"; do
    local goal fname done_count total
    goal=$(jq -r '.goal // "?"' "$pf" | head -c 60)
    fname=$(basename "$pf")
    total=$(jq '.tasks | length' "$pf")
    done_count=$(jq '[.tasks[] | select(.status == "done")] | length' "$pf")
    printf "  ${YELLOW}↻${NC} %s — %s (%d/%d tasks done)\n" "$fname" "$goal" "$done_count" "$total"
  done
  echo ""

  if [[ "$auto" == "true" && ${#interrupted[@]} -eq 1 ]]; then
    info "resuming ${interrupted[0]}..."
    _plan_execute "${interrupted[0]}" "resume"
    return $?
  fi

  info "resume with: sage plan --resume <plan-file>"
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

_plan_validate() {
  local file="$1" errors=0
  [[ -f "$file" ]] || die "file not found: $file"

  if [[ "$file" == *.yaml || "$file" == *.yml ]]; then
    local p t
    p=$(grep -E '^pattern:' "$file" | head -1 | sed 's/^pattern:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//' || true)
    t=$(grep -E '^task:' "$file" | head -1 || true)
    if [[ -z "$p" ]]; then
      echo "error: missing 'pattern' field"; errors=$((errors + 1))
    fi
    if [[ -z "$t" ]]; then
      echo "error: missing 'task' field"; errors=$((errors + 1))
    fi
  else
    # JSON plan
    if ! jq empty "$file" 2>/dev/null; then
      echo "error: invalid JSON"; return 1
    fi
    local tc
    tc=$(jq '.tasks | length' "$file" 2>/dev/null || echo 0)
    if [[ "$tc" -eq 0 ]]; then
      echo "error: missing or empty 'tasks' array"; errors=$((errors + 1))
    fi
    # Check each task has id and description
    local bad
    bad=$(jq '[.tasks[]? | select(.id == null or .description == null)] | length' "$file" 2>/dev/null || echo 0)
    if [[ "$bad" -gt 0 ]]; then
      echo "error: $bad task(s) missing id or description"; errors=$((errors + 1))
    fi
    # Cycle detection: topological sort via Kahn's algorithm in jq
    local has_cycle
    has_cycle=$(jq '
      def detect_cycle:
        .tasks as $tasks |
        [.tasks[].id] as $ids |
        [.tasks[] | {id, deps: [.depends[]? | select(. != null)]}] |
        {nodes: ., removed: []} |
        until(
          (.nodes | map(select(.deps | length == 0)) | length == 0) or (.nodes | length == 0);
          (.nodes | map(select(.deps | length == 0)) | [.[].id]) as $free |
          .removed += $free |
          .nodes = [.nodes[] | select(.deps | length > 0) | .deps -= $free]
        ) |
        if (.nodes | length) > 0 then "cycle" else "ok" end;
      detect_cycle
    ' "$file" 2>/dev/null || echo "ok")
    if [[ "$has_cycle" == '"cycle"' ]]; then
      echo "error: dependency cycle detected"; errors=$((errors + 1))
    fi
  fi

  if [[ "$errors" -eq 0 ]]; then
    echo "valid"; return 0
  fi
  return 1
}

_plan_show() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || die "plan file not found: $plan_file"

  local goal status task_count
  goal=$(jq -r '.goal // "?"' "$plan_file")
  status=$(jq -r '.status // "unknown"' "$plan_file")
  task_count=$(jq '.tasks | length' "$plan_file")

  local status_color="$NC"
  case "$status" in
    completed) status_color="$GREEN" ;;
    running)   status_color="$YELLOW" ;;
    failed|aborted) status_color="$RED" ;;
  esac

  printf "\n  ${BOLD}%s${NC}\n" "$goal"
  printf "  Status: ${status_color}%s${NC}  Tasks: %d\n\n" "$status" "$task_count"

  # Compute waves
  local wave_json
  wave_json=$(python3 -c "
import json
with open(\"$plan_file\") as f:
    plan = json.load(f)
tasks = plan.get(\"tasks\", [])
task_map = {t[\"id\"]: t for t in tasks}
waves = {}
def get_wave(tid, visited=None):
    if tid in waves: return waves[tid]
    if visited is None: visited = set()
    if tid in visited: return 1
    visited.add(tid)
    t = task_map.get(tid)
    if not t: return 1
    deps = t.get(\"depends\", [])
    if not deps: waves[tid] = 1; return 1
    waves[tid] = max(get_wave(d, visited.copy()) for d in deps) + 1
    return waves[tid]
for t in tasks:
    get_wave(t[\"id\"])
print(json.dumps(waves))
" 2>/dev/null) || { printf "  ${DIM}(cannot compute waves)${NC}\n"; return 0; }

  local max_wave
  max_wave=$(echo "$wave_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(max(d.values()) if d else 0)" 2>/dev/null)
  [[ -n "$max_wave" && "$max_wave" -gt 0 ]] || { printf "  ${DIM}no tasks${NC}\n"; return 0; }

  for w in $(seq 1 "$max_wave"); do
    printf "  ${BOLD}Wave %d${NC}\n" "$w"
    local tids
    tids=$(echo "$wave_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k, v in d.items():
    if v == $w: print(k)
" 2>/dev/null)
    while IFS= read -r tid; do
      [[ -n "$tid" ]] || continue
      local tstat tdesc
      tstat=$(jq -r ".tasks[] | select(.id == ($tid)) | .status // \"pending\"" "$plan_file")
      tdesc=$(jq -r ".tasks[] | select(.id == ($tid)) | .description // \"?\"" "$plan_file" | head -c 80)
      local icon="○"
      case "$tstat" in
        done)    icon="${GREEN}✓${NC}" ;;
        running) icon="${YELLOW}▶${NC}" ;;
        failed)  icon="${RED}✗${NC}" ;;
      esac
      printf "    %b #%-3s %-10s %s\n" "$icon" "$tid" "$tstat" "$tdesc"
    done <<< "$tids"
  done
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
      [[ -n "$name" ]] || die "usage: sage mcp rm <name> [--dry-run]"
      local mcp_file="$SAGE_HOME/mcp/${name}.json"
      [[ -f "$mcp_file" ]] || die "MCP server '$name' not found"
      if [[ "${2:-}" == "--dry-run" ]]; then
        echo "would remove MCP server '$name' at $mcp_file"
        return 0
      fi
      rm -f "$mcp_file"
      echo "removed MCP server: $name"
      ;;
    ls)
      if [[ "${1:-}" == "--json" ]]; then
        local _json="[]"
        for f in "$SAGE_HOME/mcp"/*.json; do
          [[ -f "$f" ]] || continue
          local n; n=$(basename "$f" .json)
          _json=$(jq --argjson acc "$_json" --arg n "$n" '$acc + [. + {name:$n}]' "$f")
        done
        echo "$_json"
        return
      fi
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
      if [[ "${1:-}" == "--json" ]]; then
        local _json="[]"
        for d in "$SKILLS_DIR"/*/skill.json; do
          [[ -f "$d" ]] || continue
          _json=$(jq --argjson acc "$_json" '$acc + [.]' "$d")
        done
        echo "$_json"
        return
      fi
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
      [[ -n "$name" ]] || die "usage: sage skill rm <name> [--dry-run]"
      [[ -d "$SKILLS_DIR/$name" ]] || die "skill '$name' not found"
      if [[ "${2:-}" == "--dry-run" ]]; then
        local _fc; _fc=$(find "$SKILLS_DIR/$name" -type f | wc -l | tr -d ' ')
        echo "would remove skill '$name' ($_fc file(s)) at $SKILLS_DIR/$name"
        return
      fi
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
# ═══ Dashboard ═══
_dashboard_live() {
  local agents=() selected=0
  _dash_load_agents() {
    agents=()
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n; n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      agents+=("$n")
    done
  }
  _dash_render() {
    local count=${#agents[@]}
    if [[ $count -eq 0 ]]; then
      echo "No agents found. Create one: sage create <name>"
      echo ""
      echo "  q=quit"
      return
    fi
    echo "── sage dashboard (live) ── $count agents ──"
    echo ""
    local i=0
    for n in "${agents[@]}"; do
      local rt; rt=$(jq -r '.runtime // "bash"' "$AGENTS_DIR/$n/runtime.json" 2>/dev/null || echo "bash")
      local st="stopped"
      agent_pid "$n" >/dev/null 2>&1 && st="running"
      local marker="  "
      [[ $i -eq $selected ]] && marker="> "
      printf "%s%-16s %-10s %s\n" "$marker" "$n" "$rt" "$st"
      i=$((i + 1))
    done
    echo ""
    echo "  j/k=navigate  r=restart  s=stop  l=logs  t=send task  q=quit"
  }
  _dash_load_agents
  # Non-TTY: render once and exit
  if [[ ! -t 0 ]]; then
    _dash_render
    return 0
  fi
  # Interactive loop
  trap 'tput cnorm 2>/dev/null; stty echo 2>/dev/null' EXIT
  tput civis 2>/dev/null  # hide cursor
  while true; do
    tput clear 2>/dev/null || printf '\033[2J\033[H'
    _dash_render
    local key=""
    read -rsn1 -t 2 key || true
    local count=${#agents[@]}
    case "$key" in
      q) break ;;
      j) [[ $count -gt 0 ]] && selected=$(( (selected + 1) % count )) ;;
      k) [[ $count -gt 0 ]] && selected=$(( (selected - 1 + count) % count )) ;;
      r) [[ $count -gt 0 ]] && { cmd_restart "${agents[$selected]}" 2>/dev/null; sleep 1; } ;;
      s) [[ $count -gt 0 ]] && { cmd_stop "${agents[$selected]}" 2>/dev/null; sleep 1; } ;;
      l) [[ $count -gt 0 ]] && { tput cnorm 2>/dev/null; cmd_logs "${agents[$selected]}" 2>/dev/null; } ;;
      t) [[ $count -gt 0 ]] && {
           tput cnorm 2>/dev/null
           printf "Task for %s: " "${agents[$selected]}"
           local task; read -r task
           [[ -n "$task" ]] && cmd_send "${agents[$selected]}" "$task" 2>/dev/null
           tput civis 2>/dev/null
           sleep 1
         } ;;
      "") _dash_load_agents ;;  # timeout — refresh
    esac
  done
  tput cnorm 2>/dev/null
}

cmd_dashboard() {
  ensure_init
  local json=false live=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=true; shift ;;
      --live) live=true; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  if $json && $live; then die "--json and --live are mutually exclusive"; fi
  if $live; then _dashboard_live; return; fi

  local agent_count=0
  local agents=()
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local n=$(basename "$d")
    [[ "$n" == .* ]] && continue
    agents+=("$n")
    agent_count=$((agent_count + 1))
  done

  if $json; then
    if [[ $agent_count -eq 0 ]]; then printf '[]\n'; return 0; fi
    local first=true
    printf '['
    for n in "${agents[@]}"; do
      local rt=$(jq -r '.runtime // "bash"' "$AGENTS_DIR/$n/runtime.json" 2>/dev/null || echo "bash")
      local st="stopped" pid=""
      if pid=$(agent_pid "$n" 2>/dev/null); then st="running"; fi
      $first || printf ','
      first=false
      printf '{"name":"%s","runtime":"%s","status":"%s"}' "$n" "$rt" "$st"
    done
    printf ']\n'
    return 0
  fi

  if [[ $agent_count -eq 0 ]]; then
    echo "No agents found. Create one: sage create <name>"
    return 0
  fi

  echo "── sage dashboard ── $agent_count agents ──"
  echo ""
  printf "  %-16s %-10s %s\n" "NAME" "RUNTIME" "STATUS"
  printf "  %-16s %-10s %s\n" "────" "───────" "──────"
  for n in "${agents[@]}"; do
    local rt=$(jq -r '.runtime // "bash"' "$AGENTS_DIR/$n/runtime.json" 2>/dev/null || echo "bash")
    local st="stopped"
    agent_pid "$n" >/dev/null 2>&1 && st="running"
    printf "  %-16s %-10s %s\n" "$n" "$rt" "$st"
  done
}

# ═══ Doctor ═══
_runtime_binary() {
  case "$1" in
    claude-code) echo "claude" ;;
    gemini-cli)  echo "gemini" ;;
    llama-cpp)   echo "llama-server" ;;
    acp)         echo "claude" ;;
    *)           echo "$1" ;;
  esac
}

_doctor_emit_json() {
  local jf="$1" fails="$2"
  local pass=0 warn=0 fail=0 total=0
  if [[ -s "$jf" ]]; then
    pass=$(grep -c '"status":"pass"' "$jf" || true)
    warn=$(grep -c '"status":"warn"' "$jf" || true)
    fail=$(grep -c '"status":"fail"' "$jf" || true)
  fi
  total=$((pass + warn + fail))
  printf '{"checks":['
  local first=true
  if [[ -s "$jf" ]]; then
    while IFS= read -r line; do
      $first || printf ','
      first=false
      printf '%s' "$line"
    done < "$jf"
  fi
  printf '],"summary":{"pass":%d,"warn":%d,"fail":%d,"total":%d}}\n' "$pass" "$warn" "$fail" "$total"
}

_doctor_json_check() {
  local label="$1" ok="$2" msg="$3"
  local st="pass"
  [[ "$ok" == "w" ]] && st="warn"
  [[ "$ok" == "0" ]] && st="fail"
  if [[ -n "${_DOCTOR_JSON_FILE:-}" ]]; then
    printf '%s\n' "{\"label\":$(printf '%s' "$label" | jq -Rs .),\"status\":\"$st\",\"message\":$(printf '%s' "$msg" | jq -Rs .)}" >> "$_DOCTOR_JSON_FILE"
  fi
}

_doctor_agents() {
  ensure_init
  local total=0 ok=0 fails=0
  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${BOLD}sage doctor --agents${NC}" && echo ""
  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local name rt_file runtime bin
    name=$(basename "$agent_dir")
    [[ "$name" == .* ]] && continue
    rt_file="$agent_dir/runtime.json"
    [[ -f "$rt_file" ]] || continue
    total=$((total + 1))
    runtime=$(jq -r '.runtime // "bash"' "$rt_file" 2>/dev/null)
    bin=$(_runtime_binary "$runtime")
    if command -v "$bin" >/dev/null 2>&1; then
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${GREEN}✓${NC} $name — $runtime ($bin found)"
      _doctor_json_check "$name" 1 "$runtime ($bin found)"
      ok=$((ok + 1))
    else
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${RED}✗${NC} $name — $runtime ($bin not found)"
      _doctor_json_check "$name" 0 "$runtime ($bin not found)"
      fails=$((fails + 1))
    fi
  done
  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo "" && echo "$total agent(s): $ok ok, $fails missing"
  return "$fails"
}

_doctor_security() {
  ensure_init
  local total=0 guarded=0 partial=0 none=0 fails=0
  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${BOLD}sage doctor --security${NC}" && echo ""
  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local name rt missing=""
    name=$(basename "$agent_dir")
    [[ "$name" == .* ]] && continue
    rt="$agent_dir/runtime.json"
    [[ -f "$rt" ]] || continue
    total=$((total + 1))
    local has_timeout=0 has_turns=0
    local ts mt
    ts=$(jq -r '.timeout_seconds // 0' "$rt" 2>/dev/null)
    mt=$(jq -r '.max_turns // 0' "$rt" 2>/dev/null)
    [[ "$ts" != "0" && "$ts" != "null" && -n "$ts" ]] && has_timeout=1
    [[ "$mt" != "0" && "$mt" != "null" && -n "$mt" ]] && has_turns=1
    if [[ "$has_timeout" -eq 1 && "$has_turns" -eq 1 ]]; then
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${GREEN}✓${NC} $name — guarded (timeout=${ts}s, max-turns=$mt)"
      _doctor_json_check "$name" 1 "guarded (timeout=${ts}s, max-turns=$mt)"
      guarded=$((guarded + 1))
    elif [[ "$has_timeout" -eq 1 || "$has_turns" -eq 1 ]]; then
      [[ "$has_timeout" -eq 0 ]] && missing="timeout"
      [[ "$has_turns" -eq 0 ]] && missing="max-turns"
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${YELLOW}⚠${NC} $name — missing $missing"
      _doctor_json_check "$name" "w" "missing $missing"
      partial=$((partial + 1))
    else
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${RED}✗${NC} $name — no guardrails"
      _doctor_json_check "$name" 0 "no guardrails"
      none=$((none + 1))
      fails=$((fails + 1))
    fi
  done
  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo "" && echo "$total agent(s): $guarded guarded, $partial partial, $none none"
  return "$fails"
}
_doctor_mcp() {
  local total=0 ok=0 fails=0
  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${BOLD}sage doctor --mcp${NC}" && echo ""
  for f in "$SAGE_HOME/mcp"/*.json; do
    [[ -f "$f" ]] || { [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo "no MCP servers registered"; return 0; }
    local name cmd
    name=$(basename "$f" .json)
    cmd=$(jq -r '.command // ""' "$f" 2>/dev/null)
    total=$((total + 1))
    if [[ -z "$cmd" ]]; then
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${RED}✗${NC} $name — no command defined"
      _doctor_json_check "$name" 0 "no command defined"
      fails=$((fails + 1))
    elif command -v "$cmd" >/dev/null 2>&1; then
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${GREEN}✓${NC} $name — $cmd found"
      _doctor_json_check "$name" 1 "$cmd found"
      ok=$((ok + 1))
    else
      [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${RED}✗${NC} $name — $cmd not found"
      _doctor_json_check "$name" 0 "$cmd not found"
      fails=$((fails + 1))
    fi
  done
  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo "" && echo "$total server(s): $ok ok, $fails missing"
  return "$fails"
}

cmd_doctor() {
  # Parse --json from any position
  local json_mode=false subcmd=""
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  set -- "${args[@]+"${args[@]}"}"

  if $json_mode; then
    _DOCTOR_JSON_FILE=$(mktemp)
    trap 'rm -f "$_DOCTOR_JSON_FILE"' RETURN
  fi

  local _sub="${1:-}"
  if [[ "$_sub" == "--security" ]]; then
    _doctor_security; local rc=$?
    if $json_mode; then _doctor_emit_json "$_DOCTOR_JSON_FILE" "$rc"; return $rc; fi
    return $rc
  fi
  if [[ "$_sub" == "--agents" ]]; then
    _doctor_agents; local rc=$?
    if $json_mode; then _doctor_emit_json "$_DOCTOR_JSON_FILE" "$rc"; return $rc; fi
    return $rc
  fi
  if [[ "$_sub" == "--mcp" ]]; then
    _doctor_mcp; local rc=$?
    if $json_mode; then _doctor_emit_json "$_DOCTOR_JSON_FILE" "$rc"; return $rc; fi
    return $rc
  fi
  if [[ "$_sub" == "--all" ]]; then
    local total_fails=0 r=0
    _doctor_basic; total_fails=$?
    $json_mode || echo ""
    _doctor_security; r=$?; total_fails=$((total_fails + r))
    $json_mode || echo ""
    _doctor_agents; r=$?; total_fails=$((total_fails + r))
    $json_mode || echo ""
    _doctor_mcp; r=$?; total_fails=$((total_fails + r))
    if $json_mode; then
      _doctor_emit_json "$_DOCTOR_JSON_FILE" "$total_fails"
    else
      echo ""
      if [[ "$total_fails" -eq 0 ]]; then
        echo -e "${GREEN}All checks passed (basic + security + agents + mcp).${NC}"
      else
        echo -e "${RED}$total_fails total issue(s) across all checks.${NC}"
      fi
    fi
    return "$total_fails"
  fi

  _doctor_basic; local rc=$?
  if $json_mode; then _doctor_emit_json "$_DOCTOR_JSON_FILE" "$rc"; return $rc; fi
  return $rc
}

_doctor_basic() {
  local fails=0
  _dbc() {
    local label="$1" ok="$2" msg="$3"
    _doctor_json_check "$label" "$ok" "$msg"
    if [[ -n "${_DOCTOR_JSON_FILE:-}" ]]; then
      if [[ "$ok" == "0" ]]; then fails=$((fails + 1)); fi
      return
    fi
    if [[ "$ok" == "1" ]]; then
      echo -e "${GREEN}✓${NC} $label — $msg"
    elif [[ "$ok" == "w" ]]; then
      echo -e "${YELLOW}⚠${NC} $label — $msg"
    else
      echo -e "${RED}✗${NC} $label — $msg"
      fails=$((fails + 1))
    fi
  }

  [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "${BOLD}sage doctor${NC}" && echo ""

  local bv="${BASH_VERSINFO[0]}"
  if [[ "$bv" -ge 4 ]]; then _dbc "bash" 1 "v${BASH_VERSION}"
  else _dbc "bash" "w" "v${BASH_VERSION} (4+ recommended)"; fi

  if command -v jq >/dev/null 2>&1; then _dbc "jq" 1 "$(jq --version 2>&1)"
  else _dbc "jq" 0 "not found"; fi

  if command -v tmux >/dev/null 2>&1; then _dbc "tmux" 1 "$(tmux -V 2>&1)"
  else _dbc "tmux" "w" "not found (needed for interactive sessions)"; fi

  if command -v curl >/dev/null 2>&1; then _dbc "curl" 1 "available"
  else _dbc "curl" "w" "not found (needed for API calls)"; fi

  if [[ -d "$SAGE_HOME/agents" ]]; then _dbc "sage init" 1 "$SAGE_HOME"
  else _dbc "sage init" "w" "not initialized — run: sage init"; fi

  local stale=0
  if [[ -d "$AGENTS_DIR" ]]; then
    for pidfile in "$AGENTS_DIR"/*/.pid; do
      [[ -f "$pidfile" ]] || continue
      local pid; pid=$(cat "$pidfile")
      if ! kill -0 "$pid" 2>/dev/null; then
        local aname; aname=$(basename "$(dirname "$pidfile")")
        [[ -z "${_DOCTOR_JSON_FILE:-}" ]] && echo -e "  ${YELLOW}⚠${NC} stale pid for agent '$aname' (pid $pid)"
        stale=$((stale + 1))
      fi
    done
  fi
  if [[ "$stale" -gt 0 ]]; then _dbc "agents" "w" "$stale stale pid(s) — run: sage clean"
  elif [[ -d "$AGENTS_DIR" ]]; then _dbc "agents" 1 "no stale pids"; fi

  local stale_plans=0
  if [[ -d "$PLANS_DIR" ]]; then
    for pf in "$PLANS_DIR"/*.json; do
      [[ -f "$pf" ]] || continue
      local pst; pst=$(jq -r '.status // "unknown"' "$pf" 2>/dev/null)
      [[ "$pst" == "running" ]] && stale_plans=$((stale_plans + 1))
    done
  fi
  [[ "$stale_plans" -gt 0 ]] && _dbc "plans" "w" "$stale_plans interrupted plan(s) — run: sage plan --recover"

  if [[ -z "${_DOCTOR_JSON_FILE:-}" ]]; then
    echo ""
    if [[ "$fails" -eq 0 ]]; then echo -e "${GREEN}All checks passed.${NC}"
    else echo -e "${RED}$fails issue(s) found.${NC}"; fi
    echo ""
    echo "Run --all for full check (basic + security + agents)"
  fi
  return "$fails"
}

# ═══════════════════════════════════════════════
# sage checkpoint <name|--all>
# ═══════════════════════════════════════════════
cmd_checkpoint() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "usage: sage checkpoint <name|--all|--ls>"
  ensure_init
  local ckpt_dir="$SAGE_HOME/checkpoints"
  mkdir -p "$ckpt_dir"

  if [[ "$target" == "--ls" ]]; then
    local found=false
    for ckpt in "$ckpt_dir"/*.json; do
      [[ -f "$ckpt" ]] || continue
      found=true
      local n rt ts
      n=$(basename "$ckpt" .json)
      rt=$(jq -r '.runtime // "?"' "$ckpt" 2>/dev/null)
      ts=$(jq -r '.timestamp // "?"' "$ckpt" 2>/dev/null)
      printf "  %-20s %-14s %s\n" "$n" "$rt" "$ts"
    done
    $found || info "no checkpoints"
    return
  fi

  if [[ "$target" == "--all" ]]; then
    local count=0
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local n
      n=$(basename "$agent_dir")
      [[ "$n" == .* ]] && continue
      _checkpoint_one "$n" "$ckpt_dir" && count=$((count + 1))
    done
    ok "checkpointed $count agent(s)"
  else
    agent_exists "$target"
    _checkpoint_one "$target" "$ckpt_dir"
    ok "checkpointed $target"
  fi
}

_checkpoint_one() {
  local name="$1" ckpt_dir="$2"
  local adir="$AGENTS_DIR/$name"
  local runtime
  runtime=$(jq -r '.runtime // "bash"' "$adir/runtime.json" 2>/dev/null || echo "bash")

  # Collect env vars
  local env_json="{}"
  if [[ -d "$adir/env" ]]; then
    env_json="{"
    local first=true
    for f in "$adir/env"/*; do
      [[ -f "$f" ]] || continue
      local k v
      k=$(basename "$f")
      v=$(cat "$f")
      $first || env_json="$env_json,"
      env_json="$env_json$(printf '"%s":"%s"' "$k" "$v")"
      first=false
    done
    env_json="$env_json}"
  fi

  # Collect mcp config
  local mcp_json="null"
  [[ -f "$adir/mcp.json" ]] && mcp_json=$(cat "$adir/mcp.json")

  # Collect steer file
  local steer="null"
  [[ -f "$adir/STEER.md" ]] && steer=$(jq -Rs '.' "$adir/STEER.md")

  # Check if running
  local was_running=false
  agent_pid "$name" >/dev/null 2>&1 && was_running=true

  # Write checkpoint
  printf '{"runtime":"%s","env":%s,"mcp":%s,"steer":%s,"was_running":%s,"timestamp":"%s"}\n' \
    "$runtime" "$env_json" "$mcp_json" "$steer" "$was_running" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$ckpt_dir/$name.json"
}

# ═══════════════════════════════════════════════
# sage restore [name|--all]
# ═══════════════════════════════════════════════
cmd_restore() {
  local target="${1:-}"
  ensure_init
  local ckpt_dir="$SAGE_HOME/checkpoints"

  if [[ "$target" == "--all" || -z "$target" ]]; then
    local count=0
    for ckpt in "$ckpt_dir"/*.json; do
      [[ -f "$ckpt" ]] || continue
      local n
      n=$(basename "$ckpt" .json)
      _restore_one "$n" "$ckpt_dir" && count=$((count + 1))
    done
    [[ $count -gt 0 ]] && ok "restored $count agent(s)" || die "no checkpoints found"
  else
    [[ -f "$ckpt_dir/$target.json" ]] || die "no checkpoint for '$target'"
    _restore_one "$target" "$ckpt_dir"
    ok "restored $target"
  fi
}

_restore_one() {
  local name="$1" ckpt_dir="$2"
  local ckpt="$ckpt_dir/$name.json"
  local adir="$AGENTS_DIR/$name"

  # Recreate agent dir if missing
  if [[ ! -d "$adir" ]]; then
    mkdir -p "$adir"
    local runtime
    runtime=$(jq -r '.runtime // "bash"' "$ckpt")
    printf '{"runtime":"%s"}\n' "$runtime" > "$adir/runtime.json"
  fi

  # Restore env vars
  local env_keys
  env_keys=$(jq -r '.env // {} | keys[]' "$ckpt" 2>/dev/null) || true
  if [[ -n "$env_keys" ]]; then
    mkdir -p "$adir/env"
    while IFS= read -r key; do
      jq -r ".env[\"$key\"]" "$ckpt" > "$adir/env/$key"
    done <<< "$env_keys"
  fi

  # Restore mcp config
  local mcp
  mcp=$(jq -r '.mcp // empty' "$ckpt" 2>/dev/null) || true
  if [[ -n "$mcp" && "$mcp" != "null" ]]; then
    jq '.mcp' "$ckpt" > "$adir/mcp.json"
  fi

  # Restore steer file
  local steer
  steer=$(jq -r '.steer // empty' "$ckpt" 2>/dev/null) || true
  if [[ -n "$steer" && "$steer" != "null" ]]; then
    printf '%s' "$steer" > "$adir/STEER.md"
  fi
}

# ═══════════════════════════════════════════════
# sage recover [--yes]
# ═══════════════════════════════════════════════
cmd_recover() {
  ensure_init
  local auto=false
  [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && auto=true

  local count=0

  # 1) Dead agents: have .pid but process is gone
  for pidfile in "$AGENTS_DIR"/*/.pid; do
    [[ -f "$pidfile" ]] || continue
    local pid name
    pid=$(cat "$pidfile")
    name=$(basename "$(dirname "$pidfile")")
    if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
      # Check for checkpoint
      if [[ -f "$CHECKPOINTS_DIR/${name}.json" ]]; then
        info "dead agent '$name' (pid $pid) — checkpoint found, restoring"
        if $auto; then
          rm -f "$pidfile"
          _restore_one "$name" "$CHECKPOINTS_DIR"
          count=$((count + 1))
        else
          printf "  restore '$name' from checkpoint? [y/N] "
          read -r ans
          if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
            rm -f "$pidfile"
            _restore_one "$name" "$CHECKPOINTS_DIR"
            count=$((count + 1))
          fi
        fi
      else
        info "dead agent '$name' (pid $pid) — no checkpoint, cleaning stale pid"
        rm -f "$pidfile"
        count=$((count + 1))
      fi
    fi
  done

  # 2) Checkpointed agents with no agent dir (deleted after checkpoint)
  for ckpt in "$CHECKPOINTS_DIR"/*.json; do
    [[ -f "$ckpt" ]] || continue
    local cname
    cname=$(basename "$ckpt" .json)
    if [[ ! -d "$AGENTS_DIR/$cname" ]]; then
      info "checkpointed agent '$cname' has no agent dir — restoring"
      if $auto; then
        _restore_one "$cname" "$CHECKPOINTS_DIR"
        count=$((count + 1))
      else
        printf "  restore '$cname' from checkpoint? [y/N] "
        read -r ans
        if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
          _restore_one "$cname" "$CHECKPOINTS_DIR"
          count=$((count + 1))
        fi
      fi
    fi
  done

  if [[ "$count" -eq 0 ]]; then
    ok "nothing to recover"
  else
    ok "recovered $count agent(s)"
  fi
}

cmd_alias() {
  ensure_init
  local aliasfile="$SAGE_HOME/aliases.json"
  [[ -f "$aliasfile" ]] || echo '{}' > "$aliasfile"

  local action="${1:-ls}"; shift 2>/dev/null || true

  case "$action" in
    set)
      local name="$1" expansion="$2"
      [[ -n "$name" && -n "$expansion" ]] || die "usage: sage alias set <name> <expansion>"
      local tmp; tmp=$(jq --arg k "$name" --arg v "$expansion" '.[$k]=$v' "$aliasfile")
      printf '%s\n' "$tmp" > "$aliasfile"
      ok "alias '$name' → $expansion"
      ;;
    ls)
      if [[ "${1:-}" == "--json" ]]; then
        cat "$aliasfile"
        return
      fi
      if [[ "$(jq 'length' "$aliasfile")" -eq 0 ]]; then
        printf "\n  ${DIM}no aliases defined${NC}\n\n"; return
      fi
      printf "\n${BOLD}  Aliases${NC}\n\n"
      jq -r 'to_entries[]|"  \(.key) → \(.value)"' "$aliasfile"
      printf "\n"
      ;;
    get)
      local name="${1:-}"
      [[ -n "$name" ]] || die "usage: sage alias get <name>"
      jq -e --arg k "$name" 'has($k)' "$aliasfile" >/dev/null 2>&1 || die "alias '$name' not found"
      jq -r --arg k "$name" '.[$k]' "$aliasfile"
      ;;
    rm)
      local name="$1"
      [[ -n "$name" ]] || die "usage: sage alias rm <name>"
      jq -e --arg k "$name" 'has($k)' "$aliasfile" >/dev/null 2>&1 || die "alias '$name' not found"
      local tmp; tmp=$(jq --arg k "$name" 'del(.[$k])' "$aliasfile")
      printf '%s\n' "$tmp" > "$aliasfile"
      ok "removed alias '$name'"
      ;;
    *) die "usage: sage alias [set|get|ls|rm]" ;;
  esac
}

cmd_version() {
  local verbose=false
  [[ "${1:-}" == "--verbose" || "${1:-}" == "-V" ]] && verbose=true
  if ! $verbose; then
    echo "sage $SAGE_VERSION"
    return 0
  fi
  echo "sage $SAGE_VERSION"
  echo "  bash:   $BASH_VERSION"
  local jq_v="not found"
  command -v jq >/dev/null 2>&1 && jq_v=$(jq --version 2>/dev/null)
  echo "  jq:     $jq_v"
  local tmux_v="not found"
  command -v tmux >/dev/null 2>&1 && tmux_v=$(tmux -V 2>/dev/null || echo "not found")
  echo "  tmux:   $tmux_v"
  echo "  home:   $SAGE_HOME"
  local count=0
  if [[ -d "$AGENTS_DIR" ]]; then
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n; n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      count=$((count + 1))
    done
  fi
  echo "  agents: $count"
  # Count available runtimes
  local runtimes=""
  for rt in bash claude-code cline gemini-cli codex kiro ollama llama-cpp; do
    local bin; bin=$(_runtime_binary "$rt" 2>/dev/null)
    [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && runtimes="${runtimes:+$runtimes, }$rt"
  done
  echo "  runtimes: ${runtimes:-none}"
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
  local name="" git_args=() branch_mode=false all_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)    all_mode=true; shift ;;
      --branch) branch_mode=true; shift ;;
      --stat)   git_args+=("--stat"); shift ;;
      --cached) git_args+=("--cached"); shift ;;
      -*) die "unknown flag: $1" ;;
      *)  name="$1"; shift ;;
    esac
  done
  ensure_init
  if $all_mode; then
    [[ -n "$name" ]] && die "--all cannot be combined with an agent name"
    $branch_mode && die "--all cannot be combined with --branch"
    local found=false
    for d in "$AGENTS_DIR"/*/; do
      [[ -d "$d" ]] || continue
      local n; n=$(basename "$d")
      [[ "$n" == .* ]] && continue
      local is_wt; is_wt=$(jq -r '.worktree // false' "$d/runtime.json" 2>/dev/null)
      [[ "$is_wt" == "true" ]] || continue
      local ws="$d/workspace"
      [[ -d "$ws" ]] || continue
      local diff_out; diff_out=$(git -C "$ws" diff ${git_args[@]+"${git_args[@]}"} 2>/dev/null) || continue
      [[ -n "$diff_out" ]] || continue
      found=true
      printf "${BOLD:-}=== %s ===${NC:-}\n" "$n"
      printf '%s\n\n' "$diff_out"
    done
    $found || info "no uncommitted changes in any worktree agent"
    return 0
  fi
  [[ -n "$name" ]] || die "usage: sage diff <name|--all> [--stat] [--cached] [--branch]"
  local agent_dir="$AGENTS_DIR/$name"
  [[ -d "$agent_dir" ]] || die "agent '$name' not found"
  local is_wt
  is_wt=$(jq -r '.worktree // false' "$agent_dir/runtime.json" 2>/dev/null)
  [[ "$is_wt" == "true" ]] || die "agent '$name' is not a worktree agent"
  local ws="$agent_dir/workspace"
  if $branch_mode; then
    local base
    base=$(git -C "$ws" merge-base HEAD "$(git -C "$ws" rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null || echo main)" 2>/dev/null || git -C "$ws" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
    local log_out
    log_out=$(git -C "$ws" log --oneline "$base..HEAD" 2>/dev/null)
    if [[ -n "$log_out" ]]; then
      printf "${BOLD:-}Commits:${NC:-}\n%s\n\n" "$log_out"
    fi
    git -C "$ws" diff "$base..HEAD" ${git_args[@]+"${git_args[@]}"}
  else
    git -C "$ws" diff ${git_args[@]+"${git_args[@]}"}
  fi
}

cmd_completions() {
  local shell="${1:-}"
  local cmds="attach call checkpoint clean clone completions config context create dashboard diff doctor env export help history inbox info init logs ls mcp merge msg peek plan recover rename restart restore result rm runs send skill start stats status steer stop task tasks tool trace upgrade version wait"
  case "$shell" in
    bash)
      cat <<'BASH_COMP'
_sage_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local cmds="attach call checkpoint clean clone completions config context create dashboard diff doctor env export help history inbox info init logs ls mcp merge msg peek plan recover rename restart restore result rm runs send skill start stats status steer stop task tasks tool trace upgrade version wait"
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
    return
  fi
  case "$prev" in
    ls)
      COMPREPLY=($(compgen -W "--running --stopped --failed --runtime --json -l --tree -q --quiet --sort --count" -- "$cur"));;
    logs)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--all --failed --grep --tail --since -f --clear" -- "$cur"))
      else
        local agents=""
        [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]] && agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
        COMPREPLY=($(compgen -W "$agents" -- "$cur"))
      fi;;
    stop)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--all --failed --graceful --dry-run" -- "$cur"))
      else
        local agents=""
        [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]] && agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
        COMPREPLY=($(compgen -W "$agents --all" -- "$cur"))
      fi;;
    result)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--all --failed --json --agent" -- "$cur"))
      else
        local agents=""
        [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]] && agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
        COMPREPLY=($(compgen -W "$agents" -- "$cur"))
      fi;;
    rm)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--stopped --failed --dry-run" -- "$cur"))
      else
        local agents=""
        [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]] && agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
        COMPREPLY=($(compgen -W "$agents" -- "$cur"))
      fi;;
    restart)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--all --failed --dry-run" -- "$cur"))
      else
        local agents=""
        [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]] && agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
        COMPREPLY=($(compgen -W "$agents --all" -- "$cur"))
      fi;;
    send|start|attach|peek|info|steer|wait|diff|merge|clone|rename|export|env|msg)
      local agents=""
      if [[ -d "${SAGE_HOME:-$HOME/.sage}/agents" ]]; then
        agents=$(ls "${SAGE_HOME:-$HOME/.sage}/agents" 2>/dev/null)
      fi
      COMPREPLY=($(compgen -W "$agents" -- "$cur"));;
    create)
      COMPREPLY=($(compgen -W "--runtime --worktree --mcp --skill --env --timeout --max-turns --from" -- "$cur"));;
    --runtime)
      COMPREPLY=($(compgen -W "bash claude-code cline gemini-cli codex kiro ollama llama-cpp acp" -- "$cur"));;
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
    'logs:View agent logs (flags: --all --failed --grep --tail --since -f --clear)'
    'ls:List agents (flags: --running --stopped --failed --runtime --json -l --tree -q --sort)'
    'mcp:MCP server management'
    'merge:Merge worktree branch'
    'msg:Inter-agent messaging'
    'plan:Orchestrate multi-agent plan'
    'rename:Rename an agent'
    'restart:Restart agent'
    'replay:Re-send a previous task'
    'rm:Remove agent'
    'runs:List task runs'
    'send:Send task to agent'
    'skill:Skills management'
    'start:Start agent'
    'stats:Usage statistics'
    'status:Agent status'
    'steer:Steer running agent'
    'stop:Stop agent (flags: --all --failed --graceful <duration> --dry-run)'
    'result:Get task result (flags: --all --failed --json --agent)'
    'task:Task management'
    'tasks:List tasks'
    'tool:Run agent tool'
    'trace:Trace agent execution'
    'upgrade:Self-update'
    'wait:Wait for agent completion'
    'watch:Watch directory and trigger agent on file changes'
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
  local src="" dest="" full=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full) full=true; shift ;;
      -*) die "unknown flag: $1" ;;
      *)  if [[ -z "$src" ]]; then src="$1"; else dest="$1"; fi; shift ;;
    esac
  done
  [[ -n "$src" && -n "$dest" ]] || die "usage: sage clone <source> <dest> [--full]"
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
  if $full; then
    [[ -d "$src_dir/memory" ]] && cp -r "$src_dir/memory" "$dest_dir/memory"
    [[ -f "$src_dir/env" ]] && cp "$src_dir/env" "$dest_dir/env"
  fi
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

_help_command() {
  case "$1" in
    send)
      cat << 'HELP'
  sage send <agent> <message|@file> [flags]

  Send a task to an agent. Reads from stdin when piped.

  FLAGS
    --headless      Run synchronously without tmux (required for --then/--on-fail/--retry)
    --json          Output result as JSON (requires --headless)
    --force         Cancel current task and send new one
    --then <agent>  Chain: on success, forward output to next agent
    --on-fail <cmd> Run command on failure (env: SAGE_FAIL_AGENT, SAGE_FAIL_TASK, SAGE_FAIL_OUTPUT)
    --on-done <cmd> Run command on completion (env: SAGE_DONE_AGENT, SAGE_DONE_TASK, SAGE_DONE_STATUS, SAGE_DONE_OUTPUT)
    --retry N       Retry N times on failure
    --strict        Retry if output looks incomplete (max 3 retries)
    --dry-run       Preview assembled prompt without executing
    --attach <file> Append file contents as context (max 100KB, repeatable)
    --tag <label>   Tag the task for filtering (repeatable)
    --no-context    Skip injecting shared context
    --timeout <dur> Kill task after duration (requires --headless; Nm/Nh/Ns/seconds, exit 124)
    --id <custom-id> Assign a custom task ID (alphanumeric/hyphens/underscores, max 64 chars)

  EXAMPLES
    sage send worker "Fix the login bug"
    echo "Review this" | sage send reviewer --headless --json
    sage send builder "Deploy" --headless --on-fail 'sage send ops "deploy failed"'
    sage send coder "Refactor auth" --attach src/auth.py --tag refactor
HELP
      ;;
    create)
      cat << 'HELP'
  sage create <name> [flags]

  Create a new agent.

  FLAGS
    --runtime <rt>   Runtime: bash|cline|claude-code|gemini-cli|codex|ollama|llama-cpp|acp
    --model <model>  Model name (e.g. claude-sonnet-4-20250514, qwen3:8b)
    --agent <name>   ACP agent name (with --runtime acp)
    --worktree       Create git worktree for isolation
    --mcp <server>   Attach MCP server (repeatable)
    --skill <name>   Attach skill
    --from <path|url> Import agent from archive or URL
    --env K=V        Set environment variable (repeatable)
    --allow-env K,K  Restrict env var access (allowlist)
    --timeout <dur>  Task timeout (e.g. 5m, 1h)
    --max-turns N    Max LLM turns per task

  EXAMPLES
    sage create worker --runtime claude-code
    sage create local-bot --runtime ollama --model qwen3:8b
    sage create reviewer --runtime cline --worktree --mcp github
HELP
      ;;
    plan)
      cat << 'HELP'
  sage plan <goal> [flags]
  sage plan --run <file> [flags]
  sage plan --pattern <pattern> [flags]

  Orchestrate multi-agent work with dependency waves.

  FLAGS
    --pattern <p>    Swarm pattern: fan-out, pipeline, debate, map-reduce
    --run <file>     Execute saved plan (JSON/YAML)
    --resume <file>  Resume from failure point
    --recover        Detect and resume interrupted plans
    --validate <f>   Check plan structure without executing
    --save <file>    Save generated plan to file
    --show           Visualize wave execution progress
    --yes            Auto-approve without prompting

  EXAMPLES
    sage plan "Review PR #42 for security and style"
    sage plan --pattern fan-out "Audit src/*.py" --yes
    sage plan --validate my-plan.yaml
    sage plan --run deploy-pipeline.yaml --resume deploy-pipeline.yaml
HELP
      ;;
    logs)
      cat << 'HELP'
  sage logs <name> [flags]

  View, tail, search, or clear agent logs.

  FLAGS
    -f              Follow/tail log output
    --clear         Clear log file
    --all           Show all agents' logs (color-coded)
    --grep <pat>    Search logs (case-insensitive, highlighted)

  EXAMPLES
    sage logs worker -f
    sage logs --all --grep "error"
    sage logs builder --clear
HELP
      ;;
    history)
      cat << 'HELP'
  sage history [flags]

  Show agent activity timeline.

  FLAGS
    --agent <name>  Filter by agent
    --tag <label>   Filter by task tag
    --since <dur>   Filter by age (30m, 2h, 1d, 1w)
    --grep <pat>    Search task text (case-insensitive)
    --json          Output as JSON
    -n N            Limit to N entries

  EXAMPLES
    sage history --agent worker --since 1d
    sage history --tag deploy --json
    sage history --grep "auth migration"
    sage history -n 5
HELP
      ;;
    replay)
      cat << 'HELP'
  sage replay [task-id] [flags]

  Re-send a previous task to the same agent.

  FLAGS
    --agent <name>  Override target agent
    --dry-run       Preview without sending

  EXAMPLES
    sage replay                          # replay most recent task
    sage replay task-abc123              # replay specific task
    sage replay task-abc123 --agent dev  # replay to different agent
    sage replay --dry-run                # preview what would be sent
HELP
      ;;
    config)
      cat << 'HELP'
  sage config <subcommand> [args]

  Manage global configuration key-value store.

  SUBCOMMANDS
    set <key> <value>   Set a config value (alphanumeric/dash/underscore/dot keys)
    get <key>           Get a config value
    ls [--json]         List all config (--json for machine-readable output)
    rm <key>            Remove a config key

  BUILT-IN KEYS
    default.runtime     Default runtime for new agents
    default.model       Default model for new agents
    max-agents          Max concurrent agents

  EXAMPLES
    sage config set default.runtime claude-code
    sage config get default.runtime
    sage config ls --json
    sage config rm default.model
HELP
      ;;
    context)
      cat << 'HELP'
  sage context <subcommand> [key] [value]

  Shared context store (auto-injected into all agent prompts).

  SUBCOMMANDS
    set <key> <value>       Store a key-value pair
    set <key> --file <path> Load value from file (max 100KB)
    get <key>               Retrieve a value
    ls [--json]             List all keys (--json for machine-readable output)
    rm <key>                Remove a key
    clear                   Remove all keys

  EXAMPLES
    sage context set repo_url https://github.com/org/repo
    sage context set spec --file design.md
    sage context ls --json
    sage context rm repo_url
HELP
      ;;
    env)
      cat << 'HELP'
  sage env <subcommand> <agent> [args]

  Per-agent environment variables (injected at runtime, values masked in ls).

  SUBCOMMANDS
    set <agent> KEY=VALUE [...]  Store env vars (multiple allowed)
    ls <agent> [--json]          List vars with masked values (--json for scripting)
    rm <agent> KEY               Remove a var
    scope <agent> [KEY1,KEY2]    Restrict which vars are allowed (--clear to reset)

  EXAMPLES
    sage env set worker API_KEY=sk-abc123 MODEL=gpt4
    sage env ls worker --json
    sage env rm worker API_KEY
    sage env scope worker API_KEY,MODEL
HELP
      ;;
    memory)
      cat << 'HELP'
  sage memory <subcommand> <agent> [key] [value]

  Per-agent persistent memory (auto-injected into prompts).

  SUBCOMMANDS
    set <agent> <key> <value>   Store a key-value pair
    get <agent> <key>           Retrieve a value
    ls <agent> [--json]         List all keys (--json for machine-readable output)
    rm <agent> <key>            Remove a key
    clear <agent>               Remove all keys

  EXAMPLES
    sage memory set worker api_url https://api.example.com
    sage memory get worker api_url
    sage memory ls worker --json
    sage memory clear worker
HELP
      ;;
    tool)
      cat << 'HELP'
  sage tool <subcommand> [args]

  Register, inspect, execute, and manage custom tool scripts.

  SUBCOMMANDS
    add <name> <path> [--desc "text"]  Register a tool (optional description)
    ls                                 List tools with descriptions
    rm <name> [--dry-run]              Remove a tool (--dry-run previews paths)
    run <name> [args...]               Execute a tool
    show <name>                        Show tool source

  EXAMPLES
    sage tool add lint ./scripts/lint.sh --desc "Run project linter"
    sage tool ls
    sage tool run lint src/
    sage tool rm lint
HELP
      ;;
    mcp)
      cat << 'HELP'
  sage mcp <subcommand> [args]

  Manage MCP (Model Context Protocol) servers for agents.

  SUBCOMMANDS
    add <name> --command <cmd> [--args <a,b>]  Register an MCP server
    ls                                          List registered servers
    rm <name>                                   Remove a server
    tools <agent>                               List tools exposed by agent's MCP servers
    start-servers <agent>                       Start MCP servers for an agent
    stop-servers <agent>                        Stop MCP servers for an agent
    status <agent>                              Check MCP server status

  EXAMPLES
    sage mcp add github --command npx --args -y,@modelcontextprotocol/server-github
    sage mcp ls
    sage mcp tools worker
    sage create worker --mcp github
HELP
      ;;
    skill)
      cat << 'HELP'
  sage skill <subcommand> [args]

  Install, manage, and run reusable skill packages.

  SUBCOMMANDS
    install <path|url|registry:name>  Install a skill from path, URL, or registry
    ls                                List installed skills
    rm <name>                         Remove a skill
    show <name>                       Show skill metadata and files
    run <name> [args...]              Execute a skill's run script

  EXAMPLES
    sage skill install ./my-skill
    sage skill install registry:code-review
    sage skill ls
    sage skill run code-review --file src/main.py
    sage create worker --skill code-review
HELP
      ;;
    msg)
      cat << 'HELP'
  sage msg <subcommand> [args]

  Inter-agent messaging (auto-injected on next send).

  SUBCOMMANDS
    send <from> <to> <text>  Send a message between agents
    ls <agent>               List pending messages for an agent
    clear <agent>            Clear all messages for an agent

  EXAMPLES
    sage msg send reviewer worker "Found 3 issues in auth.py"
    sage msg ls worker
    sage msg clear worker
HELP
      ;;
    *)
      echo "  No detailed help for '$1'. Showing full help:"
      echo
      cmd_help
      ;;
  esac
}

cmd_help() {
  if [[ -n "${1:-}" ]]; then
    _help_command "$1"
    return
  fi
  cat << 'EOF'

  ⚡ sage — Simple Agent Engine

  USAGE
    sage <command> [args]
    sage --version              Show version

  AGENTS
    init [--force]              Initialize sage (~/.sage/)
    create <name> [flags]       Create agent (--runtime bash|cline|claude-code|gemini-cli|codex|ollama|llama-cpp|acp, --agent <a>, --model <m>)
    start [name|--all]          Start agent(s) in tmux
    stop [name|--all]           Stop agent(s)
    restart [name|--all]        Restart agent(s)
    status [--json]             Show all agents (--json for machine-readable)
    ls                          List agent names (-l, --json, --running, --stopped, --failed, --runtime, --sort <field>)
    clone <src> <dest>          Duplicate agent config (no state)
    completions <bash|zsh>      Generate shell tab-completions
    rename <old> <new>         Rename an agent
    diff <name|--all> [--stat|--cached] Show git changes in agent worktree(s)
    export <name> [--output f]  Export agent config as tar.gz archive
                  [--format json]  JSON export for programmatic use
    rm <name>                   Remove agent
    clean                       Clean up stale files
    dashboard [--json|--live]    Agent overview: status, runtime, activity
    checkpoint <name|--all>     Save agent state to disk for later restore
    restore [name|--all]        Restore agents from checkpoints after reboot
    recover [--yes]             Detect and fix orphaned/dead agent sessions
    doctor                      Check dependencies and environment health
      [--all|--security|--agents|--mcp] [--json]
    history [--agent a] [-n N]  Show agent activity timeline (--json for JSON)
      [--prune <duration>]      Delete tasks older than duration (30m, 2h, 1d, 1w)
    info <name>                 Show full agent configuration and status (--json)
    upgrade [--check]           Self-update from GitHub (--check: compare only)
    config {set|get|ls|rm}      Persistent user defaults (e.g. default.runtime)

  MESSAGING
    send <to> <message|@file> [--force] Fire-and-forget (--force cancels, --then <agent> chains)
    call <to> <message|@file> [s]  Send and wait for response (default: 60s)
    tasks [name]                List tasks with status
      [--json] [--status <s>]   Filter by status (done, failed, running, queued)
    result <task-id>            Get task result
    replay [task-id]            Re-send a previous task
    wait <name|--all> [--timeout N] Wait for agent(s) to finish (long-running tasks)
    watch <dir> --agent <name>  Watch directory, trigger agent on file changes
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
    plan --run <file>           Execute a saved plan (JSON) or pattern file (YAML)
    plan --resume <file>        Resume from failure point
    plan --recover              Detect and resume interrupted plans
    plan --validate <file>      Validate plan YAML/JSON without executing
    plan --list                 Show saved plans

  DEBUG
    logs <name> [-f|--clear]    View/tail/clear agent logs
    logs --all [-f]             Tail all agents' logs (color-coded)
    logs --failed [--tail N]    Tail logs from only agents whose last task failed
    trace [name] [--tree] [-n N]  Show agent interaction trace
    attach [name]               Attach to tmux session

  TOOLS
    tool add <name> <path>      Register a tool
    tool ls                     List tools
    tool rm <name>              Remove a tool
    tool run <name> [args]      Execute a tool
    tool show <name>            Show tool source

  MCP SERVERS
    mcp add <name> <cmd> [args] Register an MCP server
    mcp ls                      List registered servers
    mcp rm <name>               Remove a server
    mcp tools [name]            List tools exposed by server(s)

  SKILLS
    skill install <url|path>    Install a skill from URL or local path
    skill ls                    List installed skills
    skill rm <name>             Remove a skill
    skill show <name>           Show skill details
    skill run <name> [args]     Execute a skill

  MEMORY & CONTEXT
    memory {set|get|ls|rm|clear} <agent> [key] [val]  Per-agent persistent memory
    context {set|get|ls|rm} [key] [val]               Shared context store (auto-injected)

  ENVIRONMENT
    env set <agent> <key> <val> Set per-agent env var
    env ls <agent>              List env vars
    env rm <agent> <key>        Remove env var
    env scope <agent>           Show effective env

  OBSERVABILITY
    stats [--json] [--agent <n>] Aggregate or per-agent statistics
      [--since <dur>]           Filter by time window (30m, 2h, 1d, 1w)
    stats --cost                Cost estimation per runtime
    stats --efficiency          Tasks completed per dollar

  ALIASES
    alias set <name> <command>  Create a reusable command shortcut
    alias ls                    List aliases
    alias rm <name>             Remove an alias

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
# Parse duration string (30m, 2h, 1d, 1w) → seconds
_parse_duration() {
  local d="$1"
  local num="${d%[smhdw]}" unit="${d: -1}"
  [[ "$num" =~ ^[0-9]+$ ]] || return 1
  case "$unit" in
    s) echo "$num" ;;
    m) echo $((num * 60)) ;;
    h) echo $((num * 3600)) ;;
    d) echo $((num * 86400)) ;;
    w) echo $((num * 604800)) ;;
    *) return 1 ;;
  esac
}

cmd_history() {
  ensure_init
  local agent_filter="" limit=20 json_mode=false tag_filter="" since_cutoff=0 grep_pattern="" prune_dur="" status_filter="" dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent_filter="$2"; shift 2 ;;
      -n)      limit="$2"; shift 2 ;;
      --json)  json_mode=true; shift ;;
      --tag)   tag_filter="$2"; shift 2 ;;
      --grep)  grep_pattern="$2"; shift 2 ;;
      --prune) prune_dur="$2"; shift 2 ;;
      --dry-run) dry_run=true; shift ;;
      --status) status_filter="${2:-}"; [[ -n "$status_filter" ]] || die "usage: sage history --status <done|failed>"
                case "$status_filter" in done|failed) ;; *) die "invalid status '$status_filter' (use: done, failed)" ;; esac
                shift 2 ;;
      --since) local _dur; _dur=$(_parse_duration "$2") || die "invalid duration '$2' (use: 30m, 2h, 1d, 1w)"
               since_cutoff=$(($(date +%s) - _dur)); shift 2 ;;
      *)       die "usage: sage history [--agent <name>] [--tag <label>] [--status <done|failed>] [--since <duration>] [--grep <pattern>] [--prune <duration>] [--dry-run] [-n <count>] [--json]" ;;
    esac
  done

  # --prune: delete old task history
  if [[ -n "$prune_dur" ]]; then
    local _pd
    _pd=$(_parse_duration "$prune_dur") || die "invalid duration '$prune_dur' (use: 30m, 2h, 1d, 1w)"
    local cutoff=$(($(date +%s) - _pd)) pruned=0
    for agent_dir in "$AGENTS_DIR"/*/; do
      [[ -d "$agent_dir" ]] || continue
      local aname
      aname=$(basename "$agent_dir")
      [[ "$aname" == ".cli" ]] && continue
      [[ -n "$agent_filter" && "$aname" != "$agent_filter" ]] && continue
      for sf in "$agent_dir"results/*.status.json; do
        [[ -f "$sf" ]] || continue
        local qt
        qt=$(jq -r '.queued_at // 0' "$sf" 2>/dev/null) || continue
        if [[ "$qt" -lt "$cutoff" ]]; then
          if [[ "$dry_run" == true ]]; then
            pruned=$((pruned + 1))
          else
            local base="${sf%.status.json}"
            rm -f "$sf" "${base}.result"
            pruned=$((pruned + 1))
          fi
        fi
      done
    done
    if [[ "$dry_run" == true ]]; then
      ok "would prune $pruned task(s)"
    else
      ok "pruned $pruned task(s)"
    fi
    return 0
  fi

  local entries=""
  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local aname=$(basename "$agent_dir")
    [[ "$aname" == ".cli" ]] && continue
    [[ -n "$agent_filter" && "$aname" != "$agent_filter" ]] && continue
    for sf in "$agent_dir"results/*.status.json; do
      [[ -f "$sf" ]] || continue
      # Filter by tag if requested
      if [[ -n "$tag_filter" ]]; then
        local _has_tag
        _has_tag=$(jq -r --arg t "$tag_filter" 'if (.tags // []) | index($t) then "yes" else "no" end' "$sf" 2>/dev/null) || continue
        [[ "$_has_tag" == "yes" ]] || continue
      fi
      # Filter by time if --since specified
      if [[ "$since_cutoff" -gt 0 ]]; then
        local _qt
        _qt=$(jq -r '.queued_at // 0' "$sf" 2>/dev/null) || continue
        [[ "$_qt" -ge "$since_cutoff" ]] || continue
      fi
      # Filter by grep pattern on task_text
      if [[ -n "$grep_pattern" ]]; then
        local _tt
        _tt=$(jq -r '.task_text // ""' "$sf" 2>/dev/null) || continue
        echo "$_tt" | grep -qi "$grep_pattern" || continue
      fi
      # Filter by status if --status specified
      if [[ -n "$status_filter" ]]; then
        local _st
        _st=$(jq -r '.status // ""' "$sf" 2>/dev/null) || continue
        [[ "$_st" == "$status_filter" ]] || continue
      fi
      local line
      line=$(jq -r --arg a "$aname" '. + {agent:$a} | "\(.queued_at // 0)|\(.agent)|\(.id)|\(.status)|\(.started_at // "")|\(.finished_at // "")|\(.tags // [] | join(","))|\(.task_text // "")"' "$sf" 2>/dev/null) || continue
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
    while IFS='|' read -r ts agent tid st started finished tags ttxt; do
      local dur="null"
      if [[ "$st" == "done" && -n "$finished" && "$finished" != "null" && -n "$started" && "$started" != "null" ]]; then
        dur=$((finished - started))
      fi
      local _tj="[]"
      if [[ -n "$tags" ]]; then
        IFS=',' read -ra _ta <<< "$tags"
        for _tv in "${_ta[@]}"; do
          _tj=$(echo "$_tj" | jq --arg t "$_tv" '. + [$t]')
        done
      fi
      $first || jarr="$jarr,"
      first=false
      local _ttj
      _ttj=$(printf '%s' "${ttxt:-}" | jq -Rs .)
      jarr="$jarr{\"agent\":\"$agent\",\"id\":\"$tid\",\"status\":\"$st\",\"queued_at\":$ts,\"duration\":$dur,\"tags\":$_tj,\"task_text\":$_ttj}"
    done <<< "$entries"
    echo "${jarr}]"
    return 0
  fi
  printf "  %-12s %-10s %-8s %-8s %-30s %s\n" "AGENT" "TASK" "STATUS" "DURATION" "MESSAGE" "TAGS"
  while IFS='|' read -r ts agent tid st started finished tags ttxt; do
    local dur="-"
    if [[ "$st" == "done" && -n "$finished" && "$finished" != "null" && -n "$started" && "$started" != "null" ]]; then
      dur="$((finished - started))s"
    fi
    local _tdisp="${ttxt:--}"
    [[ ${#_tdisp} -gt 30 ]] && _tdisp="${_tdisp:0:27}..."
    printf "  %-12s %-10s %-8s %-8s %-30s %s\n" "$agent" "$tid" "$st" "$dur" "$_tdisp" "${tags:--}"
  done <<< "$entries"
}

# ═══ Stats ═══
_stats_tokens() {
  local json_mode="$1"
  local total_in=0 total_out=0 json_agents="[]"

  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local aname; aname=$(basename "$agent_dir")
    [[ "$aname" == ".cli" ]] && continue
    local tf="$agent_dir/tokens.jsonl"
    [[ -f "$tf" ]] || continue
    local ain=0 aout=0
    while IFS= read -r line; do
      local i o
      i=$(echo "$line" | jq -r '.input // 0' 2>/dev/null) || continue
      o=$(echo "$line" | jq -r '.output // 0' 2>/dev/null) || continue
      [[ "$i" =~ ^[0-9]+$ ]] && ain=$((ain + i))
      [[ "$o" =~ ^[0-9]+$ ]] && aout=$((aout + o))
    done < "$tf"
    [[ "$ain" -eq 0 && "$aout" -eq 0 ]] && continue
    total_in=$((total_in + ain))
    total_out=$((total_out + aout))
    json_agents=$(echo "$json_agents" | jq --arg n "$aname" --argjson i "$ain" --argjson o "$aout" \
      '. + [{name:$n,input_tokens:$i,output_tokens:$o,total:($i+$o)}]')
  done

  if [[ "$json_mode" == "true" ]]; then
    jq -n --argjson agents "$json_agents" --argjson ti "$total_in" --argjson to "$total_out" \
      '{agents:$agents,total_input:$ti,total_output:$to,total:($ti+$to)}'
    return 0
  fi

  printf "  %-14s\n" "Tokens:"
  local count; count=$(echo "$json_agents" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    printf "    (no token data)\n"
    return 0
  fi
  echo "$json_agents" | jq -r '.[] | "    \(.name): \(.input_tokens) in / \(.output_tokens) out (\(.total) total)"'
  printf "  %-14s %s in / %s out (%s total)\n" "Total:" "$total_in" "$total_out" "$((total_in + total_out))"
}

_stats_cost() {
  local json_mode="$1"
  local cf="$SAGE_HOME/config.json"
  local total_cost=0 json_agents="[]"
  # Default pricing ($/M tokens): input, output
  _def_pricing() {
    case "$1:$2" in
      claude-code:in) echo 3;; claude-code:out) echo 15;;
      gemini-cli:in) echo 1.25;; gemini-cli:out) echo 5;;
      codex:in) echo 2.50;; codex:out) echo 10;;
      kiro:in) echo 3;; kiro:out) echo 15;;
      cline:in) echo 3;; cline:out) echo 15;;
      *) echo 0;;
    esac
  }

  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local aname; aname=$(basename "$agent_dir")
    [[ "$aname" == ".cli" ]] && continue
    local tf="$agent_dir/tokens.jsonl"
    [[ -f "$tf" ]] || continue
    local ain=0 aout=0
    while IFS= read -r line; do
      local i o
      i=$(echo "$line" | jq -r '.input // 0' 2>/dev/null) || continue
      o=$(echo "$line" | jq -r '.output // 0' 2>/dev/null) || continue
      [[ "$i" =~ ^[0-9]+$ ]] && ain=$((ain + i))
      [[ "$o" =~ ^[0-9]+$ ]] && aout=$((aout + o))
    done < "$tf"
    [[ "$ain" -eq 0 && "$aout" -eq 0 ]] && continue
    local rt; rt=$(jq -r '.runtime // "bash"' "$agent_dir/runtime.json" 2>/dev/null || echo "bash")
    # Check config overrides, then defaults
    local pin=0 pout=0
    local cfg_in; cfg_in=$(_config_get "pricing.$rt.input")
    local cfg_out; cfg_out=$(_config_get "pricing.$rt.output")
    if [[ -n "$cfg_in" ]]; then pin="$cfg_in"; else pin=$(_def_pricing "$rt" in); fi
    if [[ -n "$cfg_out" ]]; then pout="$cfg_out"; else pout=$(_def_pricing "$rt" out); fi
    # cost = tokens * (rate / 1M)
    local cost; cost=$(echo "scale=6; $ain * $pin / 1000000 + $aout * $pout / 1000000" | bc)
    # Truncate to integer for jq compatibility if whole number
    local cost_int; cost_int=$(echo "$cost" | sed 's/\.0*$//')
    [[ "$cost_int" == .* ]] && cost_int="0$cost_int"
    total_cost=$(echo "scale=6; $total_cost + $cost" | bc)
    json_agents=$(echo "$json_agents" | jq --arg n "$aname" --arg rt "$rt" \
      --argjson i "$ain" --argjson o "$aout" --argjson c "${cost_int:-0}" \
      '. + [{name:$n,runtime:$rt,input_tokens:$i,output_tokens:$o,cost_usd:$c}]')
  done

  local total_int; total_int=$(echo "$total_cost" | sed 's/\.0*$//')
  [[ "$total_int" == .* ]] && total_int="0$total_int"

  if [[ "$json_mode" == "true" ]]; then
    jq -n --argjson agents "$json_agents" --argjson tc "${total_int:-0}" \
      '{agents:$agents,total_cost_usd:$tc}'
    return 0
  fi

  printf "  %-14s\n" "Cost:"
  local count; count=$(echo "$json_agents" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    printf "    (no token data)\n"
    return 0
  fi
  echo "$json_agents" | jq -r '.[] | "    \(.name) (\(.runtime)): $\(.cost_usd)"'
  printf "  %-14s $%s\n" "Total:" "$total_int"
}

_stats_efficiency() {
  local json_mode="$1"
  local cost_json; cost_json=$(_stats_cost "true")
  local total_done=0 total_cost=0 json_agents="[]"
  local agents_arr; agents_arr=$(echo "$cost_json" | jq -c '.agents[]' 2>/dev/null) || true
  while IFS= read -r agent_line; do
    [[ -z "$agent_line" ]] && continue
    local aname; aname=$(echo "$agent_line" | jq -r '.name')
    local acost; acost=$(echo "$agent_line" | jq '.cost_usd')
    local rt; rt=$(echo "$agent_line" | jq -r '.runtime')
    local done_count=0
    for sf in "$AGENTS_DIR/$aname"/results/*.status.json; do
      [[ -f "$sf" ]] || continue
      local st; st=$(jq -r '.status // ""' "$sf" 2>/dev/null)
      [[ "$st" == "done" ]] && done_count=$((done_count + 1))
    done
    [[ "$done_count" -eq 0 && "$acost" == "0" ]] && continue
    total_done=$((total_done + done_count))
    total_cost=$(echo "scale=6; $total_cost + $acost" | bc)
    local tpd="null"
    if [[ "$acost" != "0" ]] && echo "$acost" | grep -qE '^[0-9.]+$'; then
      tpd=$(echo "scale=2; $done_count / $acost" | bc)
      [[ "$tpd" == .* ]] && tpd="0$tpd"
    fi
    json_agents=$(echo "$json_agents" | jq --arg n "$aname" --arg rt "$rt" \
      --argjson d "$done_count" --argjson c "$acost" --argjson t "$tpd" \
      '. + [{name:$n,runtime:$rt,completed_tasks:$d,cost_usd:$c,tasks_per_dollar:$t}]')
  done <<< "$agents_arr"
  local total_tpd="null"
  if echo "$total_cost" | grep -qE '^[0-9.]*[1-9]'; then
    total_tpd=$(echo "scale=2; $total_done / $total_cost" | bc)
    [[ "$total_tpd" == .* ]] && total_tpd="0$total_tpd"
  fi
  if [[ "$json_mode" == "true" ]]; then
    jq -n --argjson agents "$json_agents" --argjson td "$total_done" \
      --argjson tc "$total_cost" --argjson ttpd "$total_tpd" \
      '{agents:$agents,total_completed:$td,total_cost_usd:$tc,total_tasks_per_dollar:$ttpd}'
    return 0
  fi
  printf "  %-14s\n" "Efficiency:"
  local count; count=$(echo "$json_agents" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    printf "    (no data)\n"
    return 0
  fi
  echo "$json_agents" | jq -r '.[] | if .tasks_per_dollar == null then "    \(.name) (\(.runtime)): \(.completed_tasks) tasks, $\(.cost_usd) — N/A (free)" else "    \(.name) (\(.runtime)): \(.completed_tasks) tasks, $\(.cost_usd) — \(.tasks_per_dollar) tasks/$" end'
  if [[ "$total_tpd" == "null" ]]; then
    printf "  %-14s %d tasks, $0 — N/A\n" "Total:" "$total_done"
  else
    printf "  %-14s %d tasks, $%s — %s tasks/$\n" "Total:" "$total_done" "$(echo "$total_cost" | sed 's/\.0*$//')" "$total_tpd"
  fi
}

cmd_stats() {
  ensure_init
  local json_mode=false tokens_mode=false cost_mode=false efficiency_mode=false agent_filter="" since_cutoff=0 tag_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_mode=true; shift ;;
      --tokens) tokens_mode=true; shift ;;
      --cost) cost_mode=true; shift ;;
      --efficiency) efficiency_mode=true; shift ;;
      --agent) agent_filter="${2:-}"; [[ -n "$agent_filter" ]] || die "usage: sage stats --agent <name>"; shift 2 ;;
      --tag) tag_filter="${2:-}"; [[ -n "$tag_filter" ]] || die "usage: sage stats --tag <label>"; shift 2 ;;
      --since) local _dur; _dur=$(_parse_duration "${2:-}") || die "invalid duration '${2:-}' (use: 30m, 2h, 1d, 1w)"
               since_cutoff=$(($(date +%s) - _dur)); shift 2 ;;
      *) die "usage: sage stats [--json] [--tokens] [--cost] [--efficiency] [--agent <name>] [--tag <label>] [--since <duration>]" ;;
    esac
  done
  if [[ -n "$agent_filter" ]]; then
    [[ -d "$AGENTS_DIR/$agent_filter" ]] || die "agent '$agent_filter' not found"
  fi

  if $tokens_mode; then _stats_tokens "$json_mode"; return; fi
  if $cost_mode; then _stats_cost "$json_mode"; return; fi
  if $efficiency_mode; then _stats_efficiency "$json_mode"; return; fi

  local total_agents=0 running=0 stopped=0
  local tasks_done=0 tasks_failed=0 tasks_pending=0 total_secs=0
  local most_active_agent="" most_active_count=0

  for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    local aname; aname=$(basename "$agent_dir")
    [[ "$aname" == ".cli" ]] && continue
    [[ -n "$agent_filter" && "$aname" != "$agent_filter" ]] && continue
    total_agents=$((total_agents + 1))
    if agent_pid "$aname" >/dev/null 2>&1; then
      running=$((running + 1))
    else
      stopped=$((stopped + 1))
    fi
    local agent_tasks=0
    for sf in "$agent_dir"results/*.status.json; do
      [[ -f "$sf" ]] || continue
      if [[ "$since_cutoff" -gt 0 ]]; then
        local _sa; _sa=$(jq -r '.started_at // 0' "$sf" 2>/dev/null)
        [[ "$_sa" -ge "$since_cutoff" ]] || continue
      fi
      if [[ -n "$tag_filter" ]]; then
        local _ht; _ht=$(jq -r --arg t "$tag_filter" 'if (.tags // []) | index($t) then "y" else "n" end' "$sf" 2>/dev/null)
        [[ "$_ht" == "y" ]] || continue
      fi
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
    if [[ -n "$agent_filter" ]]; then
      jq -n --arg ag "$agent_filter" --argjson r "$running" --argjson s "$stopped" \
        --argjson td "$tasks_done" --argjson tf "$tasks_failed" --argjson tp "$tasks_pending" \
        --argjson ts "$total_secs" \
        '{agent:$ag,running:$r,stopped:$s,tasks_done:$td,tasks_failed:$tf,tasks_pending:$tp,total_runtime_secs:$ts}'
    else
      jq -n --argjson ta "$total_agents" --argjson r "$running" --argjson s "$stopped" \
        --argjson td "$tasks_done" --argjson tf "$tasks_failed" --argjson tp "$tasks_pending" \
        --argjson ts "$total_secs" --arg ma "$most_active_agent" --argjson mc "$most_active_count" \
        '{total_agents:$ta,running:$r,stopped:$s,tasks_done:$td,tasks_failed:$tf,tasks_pending:$tp,total_runtime_secs:$ts,most_active:{agent:$ma,tasks:$mc}}'
    fi
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
      if [[ "${2:-}" == "--json" ]]; then cat "$cf"; return; fi
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
      local name="${1:-}" _env_json=false
      [[ -n "$name" ]] || die "usage: sage env ls <agent> [--json]"
      [[ "${2:-}" == "--json" ]] && _env_json=true
      ensure_init; agent_exists "$name"
      local env_file="$AGENTS_DIR/$name/env"
      if [[ ! -f "$env_file" ]] || [[ ! -s "$env_file" ]]; then
        if [[ "$_env_json" == true ]]; then printf '{}\n'; else echo "  (no env vars)"; fi
        return
      fi
      if [[ "$_env_json" == true ]]; then
        local json="{}"
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -z "$line" ]] && continue
          local k="${line%%=*}" v="${line#*=}" masked
          if [[ ${#v} -le 4 ]]; then masked="****"; else masked="${v:0:2}***${v: -1}"; fi
          json=$(printf '%s' "$json" | jq --arg k "$k" --arg v "$masked" '. + {($k): $v}')
        done < "$env_file"
        printf '%s\n' "$json"
      else
        while IFS= read -r line || [[ -n "$line" ]]; do
          [[ -z "$line" ]] && continue
          local k="${line%%=*}" v="${line#*=}"
          local masked
          if [[ ${#v} -le 4 ]]; then masked="****"
          else masked="${v:0:2}***${v: -1}"
          fi
          echo "  $k=$masked"
        done < "$env_file"
      fi
      ;;
    rm)
      local name="${1:-}"; shift 2>/dev/null || true
      local key="${1:-}"
      [[ -n "$name" && -n "$key" ]] || die "usage: sage env rm <agent> KEY [--dry-run]"
      ensure_init; agent_exists "$name"
      local env_file="$AGENTS_DIR/$name/env"
      local dry_run=false
      [[ "${2:-}" == "--dry-run" ]] && dry_run=true
      if [[ "$dry_run" == true ]]; then
        if [[ -f "$env_file" ]] && grep -q "^${key}=" "$env_file" 2>/dev/null; then
          info "would remove $key from $name"
        else
          info "$key not set for $name"
        fi
        return
      fi
      [[ -f "$env_file" ]] || { warn "no env vars for $name"; return; }
      local tmp; tmp=$(grep -v "^${key}=" "$env_file" 2>/dev/null || true)
      echo "$tmp" > "$env_file"
      # Clean empty lines
      local cleaned; cleaned=$(grep -v '^$' "$env_file" 2>/dev/null || true)
      echo "$cleaned" > "$env_file"
      ok "removed $key from $name"
      ;;
    scope)
      local name="${1:-}"; shift 2>/dev/null || true
      [[ -n "$name" ]] || die "usage: sage env scope <agent> [KEY1,KEY2|--clear]"
      ensure_init; agent_exists "$name"
      local allow_file="$AGENTS_DIR/$name/allow-env"
      local arg="${1:-}"
      if [[ -z "$arg" ]]; then
        # Show current scope
        if [[ -f "$allow_file" ]]; then
          echo "  allowed: $(tr '\n' ',' < "$allow_file" | sed 's/,$//')"
        else
          echo "  scope: unrestricted (all env vars allowed)"
        fi
      elif [[ "$arg" == "--clear" ]]; then
        rm -f "$allow_file"
        ok "cleared env scope for $name (unrestricted)"
      else
        echo "$arg" | tr ',' '\n' > "$allow_file"
        ok "env scope set for $name: $arg"
      fi
      ;;
    get)
      local name="${1:-}" key="${2:-}"
      [[ -n "$name" && -n "$key" ]] || die "usage: sage env get <agent> <KEY>"
      ensure_init; agent_exists "$name"
      local env_file="$AGENTS_DIR/$name/env"
      [[ -f "$env_file" ]] || die "env var '$key' not found"
      local line; line=$(grep "^${key}=" "$env_file" 2>/dev/null | head -1) || true
      [[ -n "$line" ]] || die "env var '$key' not found"
      printf '%s\n' "${line#*=}"
      ;;
    *) die "usage: sage env <set|get|ls|rm|scope> <agent> [KEY=VALUE|KEY]" ;;
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
      [[ -n "${2:-}" ]] || die "usage: sage msg clear <agent> [--dry-run]"
      local msg_dir="$AGENTS_DIR/$2/messages"
      local count=0
      if [[ -d "$msg_dir" ]]; then
        count=$(find "$msg_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
      fi
      if [[ "${3:-}" == "--dry-run" ]]; then
        info "would clear $count message(s) for $2"
      else
        [[ -d "$msg_dir" ]] && rm -f "$msg_dir"/*.json
        info "cleared $count message(s) for $2"
      fi
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
      [[ -n "${2:-}" && -n "${3:-}" ]] || die "usage: sage context set <key> <value|--file <path>>"
      local key="$2"; shift 2
      [[ "$key" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid key '$key' — use alphanumeric, dash, underscore, dot"
      if [[ "$1" == "--file" ]]; then
        local fpath="${2:-}"
        [[ -n "$fpath" ]] || die "usage: sage context set <key> --file <path>"
        [[ -f "$fpath" ]] || die "file does not exist: $fpath"
        local sz; sz=$(wc -c < "$fpath")
        [[ $sz -le 102400 ]] || die "file too large (${sz}B > 100KB): $fpath"
        cp "$fpath" "$CONTEXT_DIR/$key"
      else
        local val="$*"
        printf '%s' "$val" > "$CONTEXT_DIR/$key"
      fi
      info "set $key"
      ;;
    get)
      [[ -n "${2:-}" ]] || die "usage: sage context get <key>"
      [[ -f "$CONTEXT_DIR/$2" ]] || die "key '$2' not found"
      cat "$CONTEXT_DIR/$2"
      ;;
    ls)
      local _ctx_json=false
      [[ "${2:-}" == "--json" ]] && _ctx_json=true
      local keys
      keys=$(ls "$CONTEXT_DIR/" 2>/dev/null)
      if [[ -z "$keys" ]]; then
        if [[ "$_ctx_json" == true ]]; then printf '[]\n'; else info "no context keys stored"; fi
      else
        if [[ "$_ctx_json" == true ]]; then
          printf '['
          local _first=true
          for k in $keys; do
            local _sz; _sz=$(wc -c < "$CONTEXT_DIR/$k")
            local _val; _val=$(cat "$CONTEXT_DIR/$k")
            _val=$(printf '%s' "$_val" | jq -Rs .)
            [[ "$_first" == true ]] && _first=false || printf ','
            printf '{"key":"%s","value":%s,"size":%d}' "$k" "$_val" "$_sz"
          done
          printf ']\n'
        else
          for k in $keys; do
            local _sz; _sz=$(wc -c < "$CONTEXT_DIR/$k")
            local _val; _val=$(cat "$CONTEXT_DIR/$k")
            if [[ ${#_val} -gt 80 ]]; then
              _val="${_val:0:80}..."
            fi
            # Replace newlines with spaces for display
            _val=$(printf '%s' "$_val" | tr '\n' ' ')
            printf "  %s = %s (%dB)\n" "$k" "$_val" "$_sz"
          done
        fi
      fi
      ;;
    rm)
      [[ -n "${2:-}" ]] || die "usage: sage context rm <key>"
      [[ -f "$CONTEXT_DIR/$2" ]] || die "key '$2' not found"
      rm "$CONTEXT_DIR/$2"
      info "removed $2"
      ;;
    clear)
      if [[ "${2:-}" == "--dry-run" ]]; then
        local _keys=() _k
        for _k in "$CONTEXT_DIR"/*; do [[ -f "$_k" ]] && _keys+=("$(basename "$_k")"); done
        info "would clear ${#_keys[@]} key(s): ${_keys[*]:-}"
        return
      fi
      rm -f "$CONTEXT_DIR"/* 2>/dev/null
      info "cleared all context"
      ;;
    *) die "usage: sage context {set|get|ls|rm|clear}" ;;
  esac
}
cmd_memory() {
  ensure_init
  local sub="${1:-}"
  local agent="${2:-}"
  [[ -n "$sub" && -n "$agent" ]] || die "usage: sage memory {set|get|ls|rm|clear} <agent> [key] [value]"
  local mem_dir="$AGENTS_DIR/$agent/memory"
  [[ -d "$AGENTS_DIR/$agent" ]] || die "agent '$agent' not found"
  mkdir -p "$mem_dir"
  case "$sub" in
    set)
      [[ -n "${3:-}" && -n "${4:-}" ]] || die "usage: sage memory set <agent> <key> <value>"
      local key="$3"; shift 3; local val="$*"
      [[ "$key" =~ ^[a-zA-Z0-9._-]+$ ]] || die "invalid key '$key'"
      printf '%s' "$val" > "$mem_dir/$key"
      info "set $key for $agent"
      ;;
    get)
      [[ -n "${3:-}" ]] || die "usage: sage memory get <agent> <key>"
      [[ -f "$mem_dir/$3" ]] || die "key '$3' not found"
      cat "$mem_dir/$3"
      ;;
    ls)
      if [[ "${3:-}" == "--json" ]]; then
        local json="{}" k
        for k in "$mem_dir"/*; do
          [[ -f "$k" ]] || continue
          json=$(printf '%s' "$json" | jq --arg k "$(basename "$k")" --arg v "$(cat "$k")" '. + {($k): $v}')
        done
        printf '%s\n' "$json"
        return
      fi
      local keys
      keys=$(ls "$mem_dir/" 2>/dev/null)
      if [[ -z "$keys" ]]; then
        info "no memory keys for $agent"
      else
        for k in $keys; do
          printf "  %s = %s\n" "$k" "$(cat "$mem_dir/$k")"
        done
      fi
      ;;
    rm)
      [[ -n "${3:-}" ]] || die "usage: sage memory rm <agent> <key>"
      [[ -f "$mem_dir/$3" ]] || die "key '$3' not found"
      rm "$mem_dir/$3"
      info "removed $3 from $agent"
      ;;
    clear)
      if [[ "${3:-}" == "--dry-run" ]]; then
        local _keys=() _k
        for _k in "$mem_dir"/*; do [[ -f "$_k" ]] && _keys+=("$(basename "$_k")"); done
        info "would clear ${#_keys[@]} key(s) for $agent: ${_keys[*]:-}"
        return
      fi
      rm -f "$mem_dir"/* 2>/dev/null
      info "cleared all memory for $agent"
      ;;
    *) die "usage: sage memory {set|get|ls|rm|clear} <agent> [key] [value]" ;;
  esac
}


# ═══ Main ═══
case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  create)  shift; cmd_create "$@" ;;
  start)   cmd_start "${2:-}" ;;
  stop)    shift; cmd_stop "$@" ;;
  restart) shift; cmd_restart "$@" ;;
  status)  shift; cmd_status "$@" ;;
  send)    shift; cmd_send "$@" ;;
  call)    shift; cmd_call "$@" ;;
  tasks)   shift; cmd_tasks "$@" ;;
  result)  shift; cmd_result "$@" ;;
  replay)  shift; cmd_replay "$@" ;;
  steer)   shift; cmd_steer "$@" ;;
  wait)    shift; cmd_wait "$@" ;;
  watch)   shift; cmd_watch "$@" ;;
  peek)    shift; cmd_peek "$@" ;;
  inbox)   shift; cmd_inbox "$@" ;;
  logs)    shift; cmd_logs "$@" ;;
  trace)   shift; cmd_trace "$@" ;;
  attach)  cmd_attach "${2:-}" ;;
  ls)      shift; cmd_ls "$@" ;;
  rm)      shift; cmd_rm "$@" ;;
  clone)   shift; cmd_clone "$@" ;;
  rename)  shift; cmd_rename "$@" ;;
  completions) shift; cmd_completions "$@" ;;
  diff)    shift; cmd_diff "$@" ;;
  export)  shift; cmd_export "$@" ;;
  merge)   shift; cmd_merge "$@" ;;
  clean)   shift; cmd_clean "$@" ;;
  tool)    shift; cmd_tool "$@" ;;
  mcp)     shift; cmd_mcp "$@" ;;
  skill)   shift; cmd_skill "$@" ;;
  context) shift; cmd_context "$@" ;;
  memory)  shift; cmd_memory "$@" ;;
  msg)     shift; cmd_msg "$@" ;;
  env)     shift; cmd_env "$@" ;;
  config)  shift; cmd_config "$@" ;;
  task)    shift; cmd_task "$@" ;;
  runs)    shift; cmd_runs "$@" ;;
  plan)    shift; cmd_plan "$@" ;;
  help|-h|--help) shift; cmd_help "$@" ;;
  "") cmd_help ;;
  dashboard) shift; cmd_dashboard "$@" ;;
  checkpoint) shift; cmd_checkpoint "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  recover) shift; cmd_recover "$@" ;;
  doctor) shift; cmd_doctor "$@" ;;
  alias)  shift; cmd_alias "$@" ;;
  history) shift; cmd_history "$@" ;;
  stats)   shift; cmd_stats "$@" ;;
  info)    shift; cmd_info "$@" ;;
  upgrade) shift; cmd_upgrade "$@" ;;
  version|--version|-v) shift 2>/dev/null || true; cmd_version "$@" ;;
  *)
    # Check aliases before failing
    _af="$SAGE_HOME/aliases.json"
    if [[ -f "$_af" ]] && jq -e --arg k "$1" 'has($k)' "$_af" >/dev/null 2>&1; then
      _exp=$(jq -r --arg k "$1" '.[$k]' "$_af")
      shift
      eval "set -- $_exp \"\$@\""
      exec "$0" "$@"
    fi
    die "unknown command: $1. Run: sage help"
    ;;
esac
