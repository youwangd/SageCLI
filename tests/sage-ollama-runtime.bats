#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ollama-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ollama runtime file exists after init" {
  [ -f "$SAGE_HOME/runtimes/ollama.sh" ]
}

@test "create agent with --runtime ollama" {
  run "$SAGE" create worker --runtime ollama
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "ollama" ]
}

@test "create agent with --runtime ollama --model qwen3:8b" {
  run "$SAGE" create worker --runtime ollama --model "qwen3:8b"
  [ "$status" -eq 0 ]
  run jq -r .model "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "qwen3:8b" ]
}

@test "ollama runtime has runtime_start function" {
  grep -q 'runtime_start()' "$SAGE_HOME/runtimes/ollama.sh"
}

@test "ollama runtime has runtime_inject function" {
  grep -q 'runtime_inject()' "$SAGE_HOME/runtimes/ollama.sh"
}

@test "ollama runtime invokes ollama run" {
  grep -q 'ollama run' "$SAGE_HOME/runtimes/ollama.sh"
}

@test "ollama runtime defaults model to llama3.2:3b" {
  grep -q 'llama3.2:3b' "$SAGE_HOME/runtimes/ollama.sh"
}

@test "ollama runtime reads instructions.md" {
  grep -q 'instructions.md' "$SAGE_HOME/runtimes/ollama.sh"
}
