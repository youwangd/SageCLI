#!/usr/bin/env bats
# tests/sage-on-fail.bats — tests for send --on-fail failure callback

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-$$"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

@test "on-fail: triggers callback on task failure" {
  local marker="$BATS_TEST_TMPDIR/fail-marker-$$"
  sage send tester "exit 1" --headless --on-fail "touch '$marker'"
  [ -f "$marker" ]
}

@test "on-fail: does NOT trigger on success" {
  local marker="$BATS_TEST_TMPDIR/success-marker-$$"
  sage send tester "echo ok" --headless --on-fail "touch '$marker'"
  [ ! -f "$marker" ]
}

@test "on-fail: env vars set in callback" {
  local out="$BATS_TEST_TMPDIR/env-out-$$"
  sage send tester "exit 1" --headless --on-fail "echo \$SAGE_FAIL_AGENT > '$out'"
  [ -f "$out" ]
  grep -q "tester" "$out"
}

@test "on-fail: requires --headless" {
  run sage send tester "echo hi" --on-fail "echo nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--headless"* ]]
}

@test "on-fail: works alongside --then (then on success, on-fail on failure)" {
  local fail_marker="$BATS_TEST_TMPDIR/combo-fail-$$"
  local then_marker="$BATS_TEST_TMPDIR/combo-then-$$"
  sage send tester "exit 1" --headless --on-fail "touch '$fail_marker'" --then tester
  [ -f "$fail_marker" ]
  [ ! -f "$then_marker" ]
}
