#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-rename-test-$$"
  "$SAGE" init 2>/dev/null
  "$SAGE" create alpha --runtime bash 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "rename moves agent directory" {
  run "$SAGE" rename alpha beta
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/beta" ]
  [ ! -d "$SAGE_HOME/agents/alpha" ]
}

@test "rename updates runtime.json name field" {
  "$SAGE" rename alpha beta
  local name
  name=$(jq -r '.name' "$SAGE_HOME/agents/beta/runtime.json")
  [ "$name" = "beta" ]
}

@test "rename preserves runtime config" {
  "$SAGE" rename alpha beta
  local rt
  rt=$(jq -r '.runtime' "$SAGE_HOME/agents/beta/runtime.json")
  [ "$rt" = "bash" ]
}

@test "rename fails if source does not exist" {
  run "$SAGE" rename nonexistent beta
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "rename fails if target already exists" {
  "$SAGE" create beta --runtime bash
  run "$SAGE" rename alpha beta
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "rename fails with invalid target name" {
  run "$SAGE" rename alpha "bad name!"
  [ "$status" -ne 0 ]
}

@test "rename requires two arguments" {
  run "$SAGE" rename alpha
  [ "$status" -ne 0 ]
  run "$SAGE" rename
  [ "$status" -ne 0 ]
}
