#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-gemini-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "gemini-cli runtime file exists after init" {
  [ -f "$SAGE_HOME/runtimes/gemini-cli.sh" ]
}

@test "create agent with --runtime gemini-cli" {
  run "$SAGE" create reviewer --runtime gemini-cli
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/reviewer/runtime.json"
  [ "$output" = "gemini-cli" ]
}

@test "gemini-cli runtime has runtime_start function" {
  grep -q 'runtime_start()' "$SAGE_HOME/runtimes/gemini-cli.sh"
}

@test "gemini-cli runtime has runtime_inject function" {
  grep -q 'runtime_inject()' "$SAGE_HOME/runtimes/gemini-cli.sh"
}

@test "gemini-cli runtime invokes gemini -p" {
  grep -q 'gemini.*-p' "$SAGE_HOME/runtimes/gemini-cli.sh"
}

@test "gemini-cli runtime uses --yolo for auto-approve" {
  grep -q '\-\-yolo' "$SAGE_HOME/runtimes/gemini-cli.sh"
}

@test "gemini-cli runtime supports model flag" {
  grep -q 'model' "$SAGE_HOME/runtimes/gemini-cli.sh"
}

@test "gemini-cli runtime sets GEMINI_SYSTEM_MD for system prompt" {
  grep -q 'GEMINI_SYSTEM_MD' "$SAGE_HOME/runtimes/gemini-cli.sh"
}

@test "create --agent gemini auto-sets acp runtime" {
  run "$SAGE" create reviewer --agent gemini
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/reviewer/runtime.json"
  [ "$output" = "acp" ]
  run jq -r .acp_agent "$SAGE_HOME/agents/reviewer/runtime.json"
  [ "$output" = "gemini" ]
}

@test "usage string mentions gemini-cli runtime" {
  run "$SAGE" help
  [[ "$output" == *"gemini-cli"* ]]
}
