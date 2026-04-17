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
  # Kill any background sleeps
  kill "$_bg_pid1" 2>/dev/null || true
  kill "$_bg_pid2" 2>/dev/null || true
  rm -rf "$SAGE_HOME"
}

# Helper: fake a running agent by writing a real PID
_fake_running() {
  sleep 300 &
  eval "_bg_pid${2:-1}=$!"
  echo "${!}" > "$SAGE_HOME/agents/$1/.pid"
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
  _fake_running a1 1
  run "$SAGE" wait --all --timeout 2
  [ "$status" -eq 124 ]
  [[ "$output" == *"timeout"* ]]
}

@test "wait --all detects completion when agent stops" {
  _fake_running a1 1
  # Kill the fake process after 1s so agent appears to complete
  ( sleep 1; kill "$_bg_pid1" 2>/dev/null ) &
  run "$SAGE" wait --all --timeout 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"a1 completed"* ]]
}
