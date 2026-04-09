#!/usr/bin/env bats
# tests/sage-commands3.bats — steer, peek, wait, attach, plan validation tests

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-cmd3-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- steer ---

@test "steer with no args fails" {
  run "$SAGE" steer
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "steer with only agent name fails" {
  run "$SAGE" steer myagent
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "steer nonexistent agent fails" {
  run "$SAGE" steer noagent "do something"
  [ "$status" -ne 0 ]
}

# --- peek ---

@test "peek with no args fails" {
  run "$SAGE" peek
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "peek nonexistent agent fails" {
  run "$SAGE" peek noagent
  [ "$status" -ne 0 ]
}

# --- wait ---

@test "wait with no args fails" {
  run "$SAGE" wait
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "wait nonexistent agent fails" {
  run "$SAGE" wait noagent
  [ "$status" -ne 0 ]
}

# --- attach ---

@test "attach with no args fails on no tmux session" {
  run "$SAGE" attach
  [ "$status" -ne 0 ]
}

# --- plan ---

@test "plan --list with no plans succeeds" {
  run "$SAGE" plan --list
  [ "$status" -eq 0 ]
}

@test "plan --run nonexistent file fails" {
  run "$SAGE" plan --run /tmp/nonexistent-plan.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "plan --resume nonexistent file fails" {
  run "$SAGE" plan --resume /tmp/nonexistent-plan.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "plan with no goal fails" {
  run "$SAGE" plan
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "steer rejects unknown flag" {
  run "$SAGE" steer --badflag
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "peek rejects unknown flag" {
  run "$SAGE" peek --badflag
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "wait rejects unknown flag" {
  run "$SAGE" wait --badflag
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}
