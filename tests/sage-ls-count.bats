#!/usr/bin/env bats
# tests/sage-ls-count.bats — ls --count prints just the matching agent count

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-count-$$"
  mkdir -p "$SAGE_HOME/agents/alpha" "$SAGE_HOME/agents/beta" "$SAGE_HOME/agents/gamma/results"
  for a in alpha beta gamma; do
    echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/$a/runtime.json"
  done
  echo '{"id":"t1","status":"failed","exit_code":1,"finished_at":100}' > "$SAGE_HOME/agents/gamma/results/t1.status.json"
  echo '{}' > "$SAGE_HOME/config.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "ls --count prints total agent count" {
  run "$BATS_TEST_DIRNAME/../sage" ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "ls --count --failed prints count of failed agents only" {
  run "$BATS_TEST_DIRNAME/../sage" ls --count --failed
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "ls --count --running prints 0 when none running" {
  run "$BATS_TEST_DIRNAME/../sage" ls --count --running
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "ls --count --runtime bash matches all 3 bash agents" {
  run "$BATS_TEST_DIRNAME/../sage" ls --count --runtime bash
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}
