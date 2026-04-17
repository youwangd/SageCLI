#!/usr/bin/env bats
# tests/sage-send-custom-id.bats — send --id assigns custom task ID

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-customid-$$"
  sage init --quiet 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "send --id uses custom task ID in result file" {
  sage send tester "echo hello" --headless --id my-task-123 >/dev/null 2>&1
  [ -f "$SAGE_HOME/agents/tester/results/my-task-123.status.json" ]
}

@test "send --id returns custom ID in --json output" {
  local out
  out=$(sage send tester "echo hello" --headless --json --id build-42 2>/dev/null)
  local tid
  tid=$(echo "$out" | jq -r '.task_id')
  [ "$tid" = "build-42" ]
}

@test "send --id rejects invalid characters" {
  run sage send tester "echo hello" --headless --id "bad id!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "send --id rejects duplicate ID" {
  sage send tester "echo hello" --headless --id unique-1 >/dev/null 2>&1
  run sage send tester "echo again" --headless --id unique-1
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}
