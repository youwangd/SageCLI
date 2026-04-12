#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-llama-cpp-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "llama-cpp runtime file exists after init" {
  [ -f "$SAGE_HOME/runtimes/llama-cpp.sh" ]
}

@test "create agent with --runtime llama-cpp" {
  run "$SAGE" create worker --runtime llama-cpp
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "llama-cpp" ]
}

@test "create agent with --runtime llama-cpp --model /path/to/model.gguf" {
  run "$SAGE" create worker --runtime llama-cpp --model "/tmp/model.gguf"
  [ "$status" -eq 0 ]
  run jq -r .model "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "/tmp/model.gguf" ]
}

@test "llama-cpp runtime has runtime_start function" {
  grep -q 'runtime_start()' "$SAGE_HOME/runtimes/llama-cpp.sh"
}

@test "llama-cpp runtime has runtime_inject function" {
  grep -q 'runtime_inject()' "$SAGE_HOME/runtimes/llama-cpp.sh"
}

@test "llama-cpp runtime invokes llama-cli" {
  grep -q 'llama-cli' "$SAGE_HOME/runtimes/llama-cpp.sh"
}

@test "llama-cpp runtime reads instructions.md" {
  grep -q 'instructions.md' "$SAGE_HOME/runtimes/llama-cpp.sh"
}
