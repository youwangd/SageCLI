#!/bin/bash
# Runtime: kiro-cli bridge
# Each message invokes kiro-cli chat --no-interactive

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
  local kiro_agent=$(jq -r '.kiro_agent // empty' "$agent_dir/runtime.json" 2>/dev/null)
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

  log "invoking kiro-cli..."
  local output
  cd "$workdir"

  local kiro_args=(chat --no-interactive --trust-all-tools)
  [[ -n "$model" ]] && kiro_args+=(--model "$model")
  [[ -n "$kiro_agent" ]] && kiro_args+=(--agent "$kiro_agent")

  local raw_file=$(mktemp /tmp/sage-kiro-out-XXXXX.txt)
  kiro-cli "${kiro_args[@]}" "$prompt" > "$raw_file" 2>&1 || true
  # Strip ANSI escapes and TUI noise
  output=$(perl -pe 's/\e\[[0-9;?]*[a-zA-Z]//g; s/\r//g' "$raw_file" 2>/dev/null | grep -v '^\s*$' | grep -v 'Credits:' | grep -v 'Learn more at' | grep -v 'WARNING:' | grep -v 'All tools are now trusted' | grep -v 'Agents can sometimes' | sed 's/^> //')
  rm -f "$raw_file"

  log "kiro-cli finished: $(echo "$output" | tail -1 | head -c 120)"

  # Echo for headless capture
  [[ -n "$output" ]] && printf '%s\n' "$output"

  local results_dir="$AGENTS_DIR/$name/results"
  if [[ -d "$results_dir" && -n "$msg_id" ]]; then
    local json_out
    json_out=$(echo "$output" | jq -Rs .) || json_out="\"encoding failed\""
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$json_out}" > "$results_dir/${msg_id}.result.json" 2>/dev/null
  fi

  if [[ -n "$reply_dir" ]]; then
    mkdir -p "$reply_dir"
    echo "{\"status\":\"done\",\"agent\":\"$name\",\"output\":$(echo "$output" | jq -Rs .)}" > "$reply_dir/${msg_id}.json"
  fi
}
