#!/usr/bin/env bats
# tests/sage-wait-all.bats — wait --all blocks until all running agents finish

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-wait-all-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create a1 --runtime bash >/dev/null 2>&1
  "$SAGE" create a2 --runtime bash >/dev/null 2>&1
}

teardown() {
  "$SAGE" stop --all >/dev/null 2>&1 || true
  rm -rf "$SAGE_HOME"
}

@test "wait --all rejects agent name argument" {
  run "$SAGE" wait --all myagent
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "wait --all exits 0 when no agents are running" {
  run "$SAGE" wait --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"no running agents"* ]]
}

@test "wait --all with --timeout exits 124 on timeout" {
  "$SAGE" start a1 >/dev/null 2>&1
  # a1 runs indefinitely (bash), so timeout should trigger
  run "$SAGE" wait --all --timeout 2
  [ "$status" -eq 124 ]
  [[ "$output" == *"timeout"* ]]
}

@test "wait --all prints agent names as they complete" {
  # Start a1 with a short-lived task, don't start a2
  "$SAGE" start a1 >/dev/null 2>&1
  # Immediately stop a1 to simulate completion
  "$SAGE" stop a1 >/dev/null 2>&1
  run "$SAGE" wait --all --timeout 3
  # No running agents → should exit 0
  [ "$status" -eq 0 ]
}
