#!/usr/bin/env bats
# tests/sage-attach-file.bats — tests for sage send --attach <file>

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-attach-$$"
  sage init --quiet 2>/dev/null || true
  sage create testbot --runtime bash 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "send --attach appends file content to message" {
  echo "hello world" > "$BATS_TEST_TMPDIR/test.txt"
  run sage send testbot "review this" --attach "$BATS_TEST_TMPDIR/test.txt" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"review this"* ]]
  [[ "$output" == *"hello world"* ]]
  [[ "$output" == *"test.txt"* ]]
}

@test "send --attach multiple files" {
  echo "file1 content" > "$BATS_TEST_TMPDIR/a.txt"
  echo "file2 content" > "$BATS_TEST_TMPDIR/b.txt"
  run sage send testbot "check both" --attach "$BATS_TEST_TMPDIR/a.txt" --attach "$BATS_TEST_TMPDIR/b.txt" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"file1 content"* ]]
  [[ "$output" == *"file2 content"* ]]
}

@test "send --attach nonexistent file fails" {
  run sage send testbot "test" --attach /nonexistent/file.txt --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "send --attach rejects files over 100KB" {
  dd if=/dev/zero of="$BATS_TEST_TMPDIR/big.txt" bs=1024 count=200 2>/dev/null
  run sage send testbot "test" --attach "$BATS_TEST_TMPDIR/big.txt" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"too large"* ]]
}

@test "send --attach works with stdin pipe" {
  echo "extra context" > "$BATS_TEST_TMPDIR/ctx.txt"
  run bash -c 'echo "piped msg" | sage send testbot --attach "'"$BATS_TEST_TMPDIR/ctx.txt"'" --dry-run'
  [ "$status" -eq 0 ]
  [[ "$output" == *"piped msg"* ]]
  [[ "$output" == *"extra context"* ]]
}
