#!/usr/bin/env bats
# tests/sage-action.bats — GitHub Action wrapper tests

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_TEST_HOME=$(mktemp -d)
  export SAGE_HOME="$SAGE_TEST_HOME"
  sage init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_TEST_HOME"
}

@test "action.yml exists and is valid YAML" {
  [[ -f "$BATS_TEST_DIRNAME/../action.yml" ]]
  # Must have required fields
  grep -q "^name:" "$BATS_TEST_DIRNAME/../action.yml"
  grep -q "^inputs:" "$BATS_TEST_DIRNAME/../action.yml"
  grep -q "task:" "$BATS_TEST_DIRNAME/../action.yml"
}

@test "action.yml defines task as required input" {
  grep -A2 "task:" "$BATS_TEST_DIRNAME/../action.yml" | grep -q "required: true"
}

@test "action.yml defines outputs" {
  grep -q "^outputs:" "$BATS_TEST_DIRNAME/../action.yml"
  grep -q "status:" "$BATS_TEST_DIRNAME/../action.yml"
  grep -q "output:" "$BATS_TEST_DIRNAME/../action.yml"
}

@test "action.yml uses sage send --headless --json" {
  grep -q "\-\-headless" "$BATS_TEST_DIRNAME/../action.yml"
  grep -q "\-\-json" "$BATS_TEST_DIRNAME/../action.yml"
}
