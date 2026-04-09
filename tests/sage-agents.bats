#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-agent-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- create ---

@test "create agent with default runtime" {
  run "$SAGE" create myworker
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/myworker" ]
  [ -f "$SAGE_HOME/agents/myworker/runtime.json" ]
  run jq -r .runtime "$SAGE_HOME/agents/myworker/runtime.json"
  [ "$output" = "bash" ]
}

@test "create agent with --runtime flag" {
  run "$SAGE" create myworker --runtime bash
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/myworker/runtime.json"
  [ "$output" = "bash" ]
}

@test "create agent with --agent auto-sets acp runtime" {
  run "$SAGE" create myworker --agent claude-code
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/myworker/runtime.json"
  [ "$output" = "acp" ]
  run jq -r .acp_agent "$SAGE_HOME/agents/myworker/runtime.json"
  [ "$output" = "claude-code" ]
}

@test "create agent creates workspace and inbox dirs" {
  run "$SAGE" create myworker
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/myworker/workspace" ]
  [ -d "$SAGE_HOME/agents/myworker/inbox" ]
  [ -d "$SAGE_HOME/agents/myworker/state" ]
  [ -d "$SAGE_HOME/agents/myworker/replies" ]
}

@test "create rejects invalid agent name" {
  run "$SAGE" create "bad name!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid agent name"* ]]
}

@test "create rejects duplicate agent" {
  "$SAGE" create myworker
  run "$SAGE" create myworker
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "create with no name fails" {
  run "$SAGE" create
  [ "$status" -ne 0 ]
}

# --- rm ---

@test "rm removes existing agent" {
  "$SAGE" create myworker
  [ -d "$SAGE_HOME/agents/myworker" ]
  run "$SAGE" rm myworker
  [ "$status" -eq 0 ]
  [ ! -d "$SAGE_HOME/agents/myworker" ]
}

@test "rm nonexistent agent fails" {
  run "$SAGE" rm ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "rm with no name fails" {
  run "$SAGE" rm
  [ "$status" -ne 0 ]
}
