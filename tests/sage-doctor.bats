#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  SAGE="$BATS_TEST_DIRNAME/../sage"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "doctor: command exists and runs" {
  run "$SAGE" doctor
  # Should produce output (not "unknown command")
  [[ "$output" != *"unknown command"* ]]
}

@test "doctor: checks bash version" {
  run "$SAGE" doctor
  [[ "$output" == *"bash"* ]]
}

@test "doctor: checks jq" {
  run "$SAGE" doctor
  [[ "$output" == *"jq"* ]]
}

@test "doctor: checks tmux" {
  run "$SAGE" doctor
  [[ "$output" == *"tmux"* ]]
}

@test "doctor: checks curl" {
  run "$SAGE" doctor
  [[ "$output" == *"curl"* ]]
}

@test "doctor: warns when sage not initialized" {
  # SAGE_HOME is empty tmpdir — not initialized
  run "$SAGE" doctor
  [[ "$output" == *"not initialized"* ]] || [[ "$output" == *"warn"* ]] || [[ "$output" == *"⚠"* ]]
}

@test "doctor: passes when initialized" {
  "$SAGE" init --force
  run "$SAGE" doctor
  [ "$status" -eq 0 ]
}

@test "doctor: detects stale agent pid" {
  "$SAGE" init --force
  mkdir -p "$SAGE_HOME/agents/stale-agent"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/stale-agent/runtime.json"
  echo "99999999" > "$SAGE_HOME/agents/stale-agent/.pid"
  run "$SAGE" doctor
  [[ "$output" == *"stale"* ]]
}
