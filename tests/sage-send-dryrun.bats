#!/usr/bin/env bats
# tests/sage-send-dryrun.bats — 5 tests for send --dry-run

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-dryrun-$$"
  sage init --quiet 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "send --dry-run prints assembled prompt without executing" {
  run sage send tester "hello world" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "send --dry-run includes injected context" {
  sage context set project "my-project" 2>/dev/null
  run sage send tester "do stuff" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Context]"* ]]
  [[ "$output" == *"project=my-project"* ]]
}

@test "send --dry-run includes agent memory" {
  sage memory set tester role "code reviewer" 2>/dev/null
  run sage send tester "review this" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Memory]"* ]]
  [[ "$output" == *"role=code reviewer"* ]]
}

@test "send --dry-run does not start the agent" {
  run sage send tester "hello" --dry-run
  [ "$status" -eq 0 ]
  # Agent should NOT be running after dry-run
  run sage ls
  [[ "$output" != *"tester"*"running"* ]]
}

@test "send --dry-run with --no-context skips injection" {
  sage context set project "my-project" 2>/dev/null
  run sage send tester "bare msg" --dry-run --no-context
  [ "$status" -eq 0 ]
  [[ "$output" == *"bare msg"* ]]
  [[ "$output" != *"[Context]"* ]]
}
