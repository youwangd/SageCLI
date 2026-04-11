#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --quiet 2>/dev/null || true
  sage create sender --runtime bash --quiet 2>/dev/null || true
  sage create receiver --runtime bash --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- msg send ---

@test "msg send delivers message to receiver" {
  run sage msg send sender receiver "found a bug in auth module"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent"* ]]
  # Message file should exist in receiver's messages dir
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 1 ]
}

@test "msg send stores correct JSON fields" {
  sage msg send sender receiver "test message"
  local msg_file=$(ls -t "$SAGE_HOME/agents/receiver/messages"/*.json 2>/dev/null | head -1)
  [ -f "$msg_file" ]
  local from=$(jq -r '.from' "$msg_file")
  local text=$(jq -r '.text' "$msg_file")
  [ "$from" = "sender" ]
  [ "$text" = "test message" ]
  # ts should be a number
  local ts=$(jq -r '.ts' "$msg_file")
  [[ "$ts" =~ ^[0-9]+$ ]]
}

@test "msg send fails with missing args" {
  run sage msg send sender
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "msg send fails for nonexistent receiver" {
  run sage msg send sender ghost "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "msg send multiple messages accumulate" {
  sage msg send sender receiver "msg1"
  sage msg send sender receiver "msg2"
  sage msg send sender receiver "msg3"
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 3 ]
}

# --- msg ls ---

@test "msg ls shows messages for agent" {
  sage msg send sender receiver "hello from sender"
  run sage msg ls receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"sender"* ]]
  [[ "$output" == *"hello from sender"* ]]
}

@test "msg ls --json outputs valid JSON" {
  sage msg send sender receiver "json test"
  run sage msg ls receiver --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "msg ls shows empty state" {
  run sage msg ls receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"no messages"* ]]
}

# --- msg clear ---

@test "msg clear removes all messages" {
  sage msg send sender receiver "msg1"
  sage msg send sender receiver "msg2"
  run sage msg clear receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 0 ]
}

@test "msg clear on empty is safe" {
  run sage msg clear receiver
  [ "$status" -eq 0 ]
}

# --- msg usage ---

@test "msg without subcommand shows usage" {
  run sage msg
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}
