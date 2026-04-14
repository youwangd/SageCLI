#!/usr/bin/env bats
# tests/sage-send-dryrun.bats — 5 tests for send --dry-run

setup() {
  export SAGE_HOME=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "send --dry-run prints assembled prompt without executing" {
  output=$(sage send tester "hello world" --dry-run 2>/dev/null)
  [[ "$output" == *"hello world"* ]]
}

@test "send --dry-run includes injected context" {
  sage context set project "my-project" 2>/dev/null
  output=$(sage send tester "do stuff" --dry-run 2>/dev/null)
  [[ "$output" == *"[Context]"* ]]
  [[ "$output" == *"project=my-project"* ]]
}

@test "send --dry-run includes agent memory" {
  sage memory set tester role "code reviewer" 2>/dev/null
  output=$(sage send tester "review this" --dry-run 2>/dev/null)
  [[ "$output" == *"[Memory]"* ]]
  [[ "$output" == *"role=code reviewer"* ]]
}

@test "send --dry-run does not start the agent" {
  sage send tester "hello" --dry-run 2>/dev/null
  # Agent should NOT be running after dry-run
  run sage status tester 2>/dev/null
  [[ "$output" != *"running"* ]] || [[ "$status" -ne 0 ]]
}

@test "send --dry-run works with --no-context to skip injection" {
  sage context set project "my-project" 2>/dev/null
  output=$(sage send tester "bare msg" --dry-run --no-context 2>/dev/null)
  [[ "$output" == *"bare msg"* ]]
  [[ "$output" != *"[Context]"* ]]
}
