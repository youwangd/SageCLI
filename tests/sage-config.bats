#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-config-test-$$"
  "$SAGE" init 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "sage config set stores a value" {
  run "$SAGE" config set default.runtime claude-code
  [ "$status" -eq 0 ]
  [[ "$output" == *"default.runtime"* ]]
}

@test "sage config get retrieves a value" {
  "$SAGE" config set default.runtime claude-code
  run "$SAGE" config get default.runtime
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code"* ]]
}

@test "sage config get missing key fails" {
  run "$SAGE" config get nonexistent
  [ "$status" -ne 0 ]
}

@test "sage config ls shows all keys" {
  "$SAGE" config set default.runtime bash
  "$SAGE" config set default.model sonnet
  run "$SAGE" config ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"default.runtime"* ]]
  [[ "$output" == *"default.model"* ]]
}

@test "sage config rm removes a key" {
  "$SAGE" config set default.runtime bash
  "$SAGE" config rm default.runtime
  run "$SAGE" config get default.runtime
  [ "$status" -ne 0 ]
}

@test "sage config rejects invalid key names" {
  run "$SAGE" config set "bad key!" value
  [ "$status" -ne 0 ]
}

@test "sage create uses default.runtime from config" {
  "$SAGE" config set default.runtime claude-code
  run "$SAGE" create testbot
  [ "$status" -eq 0 ]
  run cat "$SAGE_HOME/agents/testbot/runtime.json"
  [[ "$output" == *"claude-code"* ]]
}

@test "sage create --runtime overrides config default" {
  "$SAGE" config set default.runtime claude-code
  run "$SAGE" create testbot --runtime bash
  [ "$status" -eq 0 ]
  run cat "$SAGE_HOME/agents/testbot/runtime.json"
  [[ "$output" == *"bash"* ]]
}

@test "sage help includes config command" {
  run "$SAGE" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"config"* ]]
}
