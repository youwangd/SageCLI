#!/usr/bin/env bats
# Tests for env var allowlist / scoping

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-envscope-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create scopebot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "create --allow-env stores allowlist file" {
  "$SAGE" create restricted --allow-env "API_KEY,HOME" >/dev/null 2>&1
  [ -f "$SAGE_HOME/agents/restricted/allow-env" ]
  grep -q "API_KEY" "$SAGE_HOME/agents/restricted/allow-env"
  grep -q "HOME" "$SAGE_HOME/agents/restricted/allow-env"
}

@test "env scope set writes allowlist" {
  run "$SAGE" env scope scopebot API_KEY,SECRET
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/scopebot/allow-env" ]
  grep -q "API_KEY" "$SAGE_HOME/agents/scopebot/allow-env"
  grep -q "SECRET" "$SAGE_HOME/agents/scopebot/allow-env"
}

@test "env scope show lists allowed keys" {
  "$SAGE" env scope scopebot FOO,BAR >/dev/null 2>&1
  run "$SAGE" env scope scopebot
  [ "$status" -eq 0 ]
  [[ "$output" == *"FOO"* ]]
  [[ "$output" == *"BAR"* ]]
}

@test "env scope --clear removes allowlist" {
  "$SAGE" env scope scopebot X,Y >/dev/null 2>&1
  [ -f "$SAGE_HOME/agents/scopebot/allow-env" ]
  run "$SAGE" env scope scopebot --clear
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/scopebot/allow-env" ]
}

@test "env scope with no allowlist shows unrestricted" {
  run "$SAGE" env scope scopebot
  [ "$status" -eq 0 ]
  [[ "$output" == *"unrestricted"* ]]
}
