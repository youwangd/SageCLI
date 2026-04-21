#!/usr/bin/env bats
# tests/sage-msg-ls-count.bats — msg ls <agent> --count prints plain integer

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-msg-count-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  mkdir -p "$SAGE_HOME/agents/sender" "$SAGE_HOME/agents/receiver"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "msg ls --count prints 0 when no messages" {
  run "$SAGE" msg ls receiver --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "msg ls --count prints integer matching message count" {
  "$SAGE" msg send sender receiver "one" >/dev/null
  "$SAGE" msg send sender receiver "two" >/dev/null
  "$SAGE" msg send sender receiver "three" >/dev/null
  run "$SAGE" msg ls receiver --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "msg ls --count output is scriptable (pure digits)" {
  "$SAGE" msg send sender receiver "hello" >/dev/null
  local n
  n=$("$SAGE" msg ls receiver --count)
  [[ "$n" =~ ^[0-9]+$ ]]
  [ "$n" -eq 1 ]
}
