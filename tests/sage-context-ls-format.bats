#!/usr/bin/env bats
# tests/sage-context-ls-format.bats — tests for context ls truncation, size, and --json

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ctxls-fmt-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "context ls truncates values longer than 80 chars" {
  local long_val
  long_val=$(printf 'A%.0s' $(seq 1 120))
  "$SAGE" context set longkey "$long_val"
  run "$SAGE" context ls
  [ "$status" -eq 0 ]
  # Should show truncated value with ... not the full 120 chars
  [[ "$output" == *"..."* ]]
  # Should NOT contain the full 120-char string
  [[ "$output" != *"$long_val"* ]]
}

@test "context ls shows byte size for each key" {
  "$SAGE" context set small "hello"
  run "$SAGE" context ls
  [ "$status" -eq 0 ]
  # Should show size like (5B) or similar
  [[ "$output" == *"5B"* ]]
}

@test "context ls short values shown in full" {
  "$SAGE" context set mykey "short value"
  run "$SAGE" context ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"short value"* ]]
}

@test "context ls --json outputs valid JSON array" {
  "$SAGE" context set alpha "one"
  "$SAGE" context set beta "two"
  run "$SAGE" context ls --json
  [ "$status" -eq 0 ]
  # Must be valid JSON
  echo "$output" | jq . >/dev/null 2>&1
  # Must contain both keys
  echo "$output" | jq -e '.[].key' | grep -q alpha
  echo "$output" | jq -e '.[].key' | grep -q beta
  # Must have size field
  echo "$output" | jq -e '.[0].size' >/dev/null
}
