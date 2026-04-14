#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  SAGE="$BATS_TEST_DIRNAME/../sage"
  "$SAGE" init --force >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

_make_agent() {
  local name="$1"
  shift
  mkdir -p "$SAGE_HOME/agents/$name"
  local json='{"runtime":"bash"'
  while [[ $# -gt 0 ]]; do
    json="$json,\"$1\":$2"
    shift 2
  done
  json="$json}"
  echo "$json" > "$SAGE_HOME/agents/$name/runtime.json"
}

@test "doctor --all: runs basic checks section" {
  run "$SAGE" doctor --all
  [[ "$output" == *"sage doctor"* ]]
  [[ "$output" == *"bash"* ]]
  [[ "$output" == *"jq"* ]]
}

@test "doctor --all: runs security section" {
  _make_agent "myagent"
  run "$SAGE" doctor --all
  [[ "$output" == *"security"* ]] || [[ "$output" == *"Security"* ]]
  [[ "$output" == *"myagent"* ]]
}

@test "doctor --all: runs agents section" {
  _make_agent "myagent"
  run "$SAGE" doctor --all
  [[ "$output" == *"agent"* ]]
  [[ "$output" == *"bash"* ]]
}

@test "doctor --all: exits 0 when all healthy" {
  _make_agent "good" timeout_seconds 300 max_turns 20
  run "$SAGE" doctor --all
  [[ "$status" -eq 0 ]]
}

@test "doctor: bare command mentions --all flag" {
  run "$SAGE" doctor
  [[ "$output" == *"--all"* ]]
}
