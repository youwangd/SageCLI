#!/usr/bin/env bats
# tests/sage-context-file.bats — tests for sage context set --file

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ctxfile-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "context set --file loads value from file" {
  echo "project spec contents here" > "$BATS_TMPDIR/spec.md"
  run "$SAGE" context set myspec --file "$BATS_TMPDIR/spec.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$SAGE_HOME/context/myspec")" = "project spec contents here" ]
}

@test "context set --file errors on nonexistent file" {
  run "$SAGE" context set myspec --file /tmp/no-such-file-ever.txt
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* || "$output" == *"does not exist"* ]]
}

@test "context set --file errors on file over 100KB" {
  dd if=/dev/zero bs=1024 count=110 of="$BATS_TMPDIR/bigfile.txt" 2>/dev/null
  run "$SAGE" context set myspec --file "$BATS_TMPDIR/bigfile.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too large"* ]]
}

@test "context set inline still works (backward compat)" {
  run "$SAGE" context set mykey "hello world"
  [ "$status" -eq 0 ]
  [ "$(cat "$SAGE_HOME/context/mykey")" = "hello world" ]
}

@test "context set --file preserves multiline content" {
  printf "line1\nline2\nline3" > "$BATS_TMPDIR/multi.txt"
  run "$SAGE" context set readme --file "$BATS_TMPDIR/multi.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$SAGE_HOME/context/readme")" = "$(printf 'line1\nline2\nline3')" ]
}
