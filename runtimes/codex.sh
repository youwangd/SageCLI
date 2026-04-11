#!/bin/bash
# Runtime: codex CLI bridge (via LiteLLM → Bedrock)
# Requires LiteLLM proxy on localhost:4000 and ~/.codex/config.toml with litellm provider

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
  [[ -z "$model" ]] && model="claude-sonnet"

  log "invoking codex..."
  local output
  cd "$workdir"

  output=$(echo "$task" | codex exec --full-auto --skip-git-repo-check -p bedrock -m "$model" "$task" 2>&1) || true
  # Strip codex chrome (token counts, warnings)
  output=$(printf '%s' "$output" | grep -v "^warning:" | grep -v "^tokens used" | grep -v "^[0-9,]*$" | grep -v "^codex$" | grep -v "^--------" | grep -v "^user$" | grep -v "^<stdin>" | grep -v "^</stdin>" | sed '/^$/d')

  log "codex finished: $(echo "$output" | tail -1 | head -c 120)"

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
