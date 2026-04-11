#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-msg-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  # Create agent dirs directly (no runtime needed for msg tests)
  mkdir -p "$SAGE_HOME/agents/sender" "$SAGE_HOME/agents/receiver"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- msg send ---

@test "msg send delivers message to receiver" {
  run "$SAGE" msg send sender receiver "found a bug in auth module"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent"* ]]
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 1 ]
}

@test "msg send stores correct JSON fields" {
  "$SAGE" msg send sender receiver "test message"
  local msg_file=$(ls -t "$SAGE_HOME/agents/receiver/messages"/*.json 2>/dev/null | head -1)
  [ -f "$msg_file" ]
  local from=$(jq -r '.from' "$msg_file")
  local text=$(jq -r '.text' "$msg_file")
  [ "$from" = "sender" ]
  [ "$text" = "test message" ]
  local ts=$(jq -r '.ts' "$msg_file")
  [[ "$ts" =~ ^[0-9]+$ ]]
}

@test "msg send fails with missing args" {
  run "$SAGE" msg send sender
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "msg send fails for nonexistent receiver" {
  run "$SAGE" msg send sender ghost "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "msg send multiple messages accumulate" {
  "$SAGE" msg send sender receiver "msg1"
  sleep 1
  "$SAGE" msg send sender receiver "msg2"
  sleep 1
  "$SAGE" msg send sender receiver "msg3"
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 3 ]
}

# --- msg ls ---

@test "msg ls shows messages for agent" {
  "$SAGE" msg send sender receiver "hello from sender"
  run "$SAGE" msg ls receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"sender"* ]]
  [[ "$output" == *"hello from sender"* ]]
}

@test "msg ls --json outputs valid JSON" {
  "$SAGE" msg send sender receiver "json test"
  run "$SAGE" msg ls receiver --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "msg ls shows empty state" {
  run "$SAGE" msg ls receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"no messages"* ]]
}

# --- msg clear ---

@test "msg clear removes all messages" {
  "$SAGE" msg send sender receiver "msg1"
  "$SAGE" msg send sender receiver "msg2"
  run "$SAGE" msg clear receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 0 ]
}

@test "msg clear on empty is safe" {
  run "$SAGE" msg clear receiver
  [ "$status" -eq 0 ]
}

# --- msg usage ---

@test "msg without subcommand shows usage" {
  run "$SAGE" msg
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}
