#!/usr/bin/env bats
# tests/sage-send-output-file.bats — send --output-file writes task output to file

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-outfile-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create tester --runtime bash >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "send --output-file writes task output to file" {
  local outfile="$BATS_TMPDIR/out-$$.txt"
  run "$SAGE" send tester "echo hello" --headless --output-file "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  grep -q "hello" "$outfile"
}

@test "send --output-file with --json writes JSON to file" {
  local outfile="$BATS_TMPDIR/out-json-$$.txt"
  run "$SAGE" send tester "echo hello" --headless --json --output-file "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  local st
  st=$(jq -r '.status' "$outfile")
  [ "$st" = "done" ]
}

@test "send --output-file creates parent directories" {
  local outfile="$BATS_TMPDIR/deep/nested/dir-$$/out.txt"
  run "$SAGE" send tester "echo nested" --headless --output-file "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  grep -q "nested" "$outfile"
}

@test "send --output-file requires --headless" {
  run "$SAGE" send tester "echo hello" --output-file /tmp/x.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"--headless"* ]]
}
