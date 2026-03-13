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

  log "invoking cline (reply_dir=${reply_dir:-none}, msg_id=${msg_id})..."
  local output=""
  cd "$workdir"

  local cline_args=(--act -c "$workdir")
  [[ -n "$model" ]] && cline_args+=(-m "$model")

  output=$(cline "${cline_args[@]}" "$(cat "$prompt_file")" 2>&1) || true
  rm -f "$prompt_file"

  local output_len=${#output}
  log "cline finished (${output_len} bytes): $(echo "$output" | tail -1 | head -c 120)"

  # Write reply for sync calls
  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir" 2>/dev/null || true
    local reply_file="$reply_dir/${msg_id}.json"
    local json_output
    json_output=$(echo "$output" | jq -Rs .) || json_output="\"output encoding failed\""
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_output}" > "$reply_file"
    log "reply written to $reply_file ($(wc -c < "$reply_file") bytes)"
  else
    log "no reply_dir, skipping reply"
  fi
}
