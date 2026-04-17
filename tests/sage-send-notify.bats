#!/usr/bin/env bats
# tests/sage-send-notify.bats — send --notify rings terminal bell on task completion

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-notify-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create tester --runtime bash >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "send --notify is accepted as a valid flag" {
  run "$SAGE" send tester "echo hi" --headless --notify
  [ "$status" -eq 0 ]
}

@test "send --notify output ends with BEL character" {
  local tmpf="$BATS_TMPDIR/notify-out-$$"
  "$SAGE" send tester "echo hi" --headless --notify > "$tmpf" 2>&1 || true
  # Last bytes should contain \x07 (BEL)
  tail -c 4 "$tmpf" | od -An -tx1 | tr -d ' \n' | grep -q "07"
}

@test "send without --notify has no trailing BEL" {
  local tmpf="$BATS_TMPDIR/no-notify-out-$$"
  "$SAGE" send tester "echo hi" --headless > "$tmpf" 2>&1 || true
  # Should NOT have BEL in last bytes
  if tail -c 4 "$tmpf" | od -An -tx1 | tr -d ' \n' | grep -q "07"; then
    false
  fi
}

@test "send --notify works with --json" {
  run "$SAGE" send tester "echo hi" --headless --json --notify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"status"'
}
