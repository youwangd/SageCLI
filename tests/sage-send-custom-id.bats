#!/usr/bin/env bats
# tests/sage-send-custom-id.bats — send --id assigns custom task ID

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-customid-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create tester --runtime bash >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "send --id uses custom task ID in result file" {
  run "$SAGE" send tester "echo hello" --headless --id my-task-123
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/tester/results/my-task-123.status.json" ]
}

@test "send --id returns custom ID in --json output" {
  run "$SAGE" send tester "echo hello" --headless --json --id build-42
  [ "$status" -eq 0 ]
  local tid
  tid=$(echo "$output" | jq -r '.task_id')
  [ "$tid" = "build-42" ]
}

@test "send --id rejects invalid characters" {
  run "$SAGE" send tester "echo hello" --headless --id "bad id!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "send --id rejects duplicate ID" {
  "$SAGE" send tester "echo hello" --headless --id unique-1 >/dev/null 2>&1
  run "$SAGE" send tester "echo again" --headless --id unique-1
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}
