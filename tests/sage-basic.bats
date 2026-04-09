#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

@test "sage --help shows usage" {
  run "$SAGE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage"* ]]
  [[ "$output" == *"USAGE"* ]]
}

@test "sage help shows usage" {
  run "$SAGE" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
}

@test "sage with no args shows help" {
  run "$SAGE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
}

@test "sage init creates SAGE_HOME directory" {
  export SAGE_HOME="$BATS_TMPDIR/sage-test-$$"
  rm -rf "$SAGE_HOME"
  run "$SAGE" init
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME" ]
  [ -d "$SAGE_HOME/agents" ]
  [ -d "$SAGE_HOME/tools" ]
  rm -rf "$SAGE_HOME"
}

@test "sage init --force reinitializes" {
  export SAGE_HOME="$BATS_TMPDIR/sage-test-$$"
  rm -rf "$SAGE_HOME"
  run "$SAGE" init
  [ "$status" -eq 0 ]
  run "$SAGE" init --force
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME" ]
  rm -rf "$SAGE_HOME"
}

@test "sage init warns if already initialized" {
  export SAGE_HOME="$BATS_TMPDIR/sage-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init
  run "$SAGE" init
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
  rm -rf "$SAGE_HOME"
}

@test "sage unknown command fails" {
  run "$SAGE" nonexistent_command_xyz
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
}
