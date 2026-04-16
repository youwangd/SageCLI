#!/usr/bin/env bats
# tests/sage-clone-full.bats — clone --full copies memory and env

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-clone-full-$$"
  "$SAGE" init 2>/dev/null
  "$SAGE" create original --runtime bash 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "clone --full copies memory directory" {
  mkdir -p "$SAGE_HOME/agents/original/memory"
  echo "bar" > "$SAGE_HOME/agents/original/memory/foo"
  run "$SAGE" clone original copy1 --full
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/copy1/memory/foo" ]
  run cat "$SAGE_HOME/agents/copy1/memory/foo"
  [ "$output" = "bar" ]
}

@test "clone --full copies env file" {
  echo "API_KEY=secret123" > "$SAGE_HOME/agents/original/env"
  run "$SAGE" clone original copy1 --full
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/copy1/env" ]
  run cat "$SAGE_HOME/agents/copy1/env"
  [[ "$output" == *"API_KEY=secret123"* ]]
}

@test "clone without --full does NOT copy memory" {
  mkdir -p "$SAGE_HOME/agents/original/memory"
  echo "bar" > "$SAGE_HOME/agents/original/memory/foo"
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/copy1/memory/foo" ]
}

@test "clone --full with no memory/env still succeeds" {
  run "$SAGE" clone original copy1 --full
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/copy1" ]
}
