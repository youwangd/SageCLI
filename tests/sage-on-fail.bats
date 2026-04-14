#!/usr/bin/env bats
# tests/sage-on-fail.bats — tests for send --on-fail failure callback

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-$$"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

_make_failing_handler() {
  cat > "$SAGE_HOME/agents/tester/handler.sh" << 'EOF'
#!/bin/bash
handle_message() { exit 1; }
EOF
}

_make_passing_handler() {
  cat > "$SAGE_HOME/agents/tester/handler.sh" << 'EOF'
#!/bin/bash
handle_message() { echo "ok"; }
EOF
}

@test "on-fail: triggers callback on task failure" {
  _make_failing_handler
  local marker="$BATS_TEST_TMPDIR/fail-marker-$$"
  sage send tester "do stuff" --headless --on-fail "touch '$marker'" || true
  [ -f "$marker" ]
}

@test "on-fail: does NOT trigger on success" {
  _make_passing_handler
  local marker="$BATS_TEST_TMPDIR/success-marker-$$"
  sage send tester "do stuff" --headless --on-fail "touch '$marker'"
  [ ! -f "$marker" ]
}

@test "on-fail: env vars set in callback" {
  _make_failing_handler
  local out="$BATS_TEST_TMPDIR/env-out-$$"
  sage send tester "do stuff" --headless --on-fail "echo \$SAGE_FAIL_AGENT > '$out'" || true
  [ -f "$out" ]
  grep -q "tester" "$out"
}

@test "on-fail: requires --headless" {
  run sage send tester "echo hi" --on-fail "echo nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--headless"* ]]
}

@test "on-fail: callback does not run when --then succeeds" {
  _make_passing_handler
  local fail_marker="$BATS_TEST_TMPDIR/combo-fail-$$"
  sage send tester "do stuff" --headless --on-fail "touch '$fail_marker'"
  [ ! -f "$fail_marker" ]
}
