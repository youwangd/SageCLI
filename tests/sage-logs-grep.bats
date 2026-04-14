#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-grep-$$"
  sage init --quiet 2>/dev/null || true
  sage create worker --runtime bash --quiet 2>/dev/null || true
  mkdir -p "$SAGE_HOME/logs"
  printf '%s\n' "INFO: starting task" "ERROR: connection failed" "INFO: retrying" "ERROR: timeout reached" "INFO: task complete" > "$SAGE_HOME/logs/worker.log"
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "logs --grep filters matching lines" {
  run sage logs worker --grep "ERROR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"connection failed"* ]]
  [[ "$output" == *"timeout reached"* ]]
  [[ "$output" != *"task complete"* ]]
}

@test "logs --grep with no matches exits cleanly" {
  run sage logs worker --grep "FATAL"
  [ "$status" -eq 0 ]
}

@test "logs --grep is case-insensitive" {
  run sage logs worker --grep "error"
  [ "$status" -eq 0 ]
  [[ "$output" == *"connection failed"* ]]
}

@test "logs --all --grep filters across agents" {
  sage create helper --runtime bash --quiet 2>/dev/null || true
  printf '%s\n' "DEBUG: helper started" "ERROR: helper crashed" > "$SAGE_HOME/logs/helper.log"
  run sage logs --all --grep "ERROR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"connection failed"* ]]
  [[ "$output" == *"helper crashed"* ]]
  [[ "$output" != *"helper started"* ]]
}

@test "logs --grep requires pattern argument" {
  run sage logs worker --grep
  [ "$status" -ne 0 ]
}
