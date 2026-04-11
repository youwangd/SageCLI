#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-codex-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "codex runtime file exists after init" {
  [ -f "$SAGE_HOME/runtimes/codex.sh" ]
}

@test "create agent with --runtime codex" {
  run "$SAGE" create reviewer --runtime codex
  [ "$status" -eq 0 ]
  run jq -r .runtime "$SAGE_HOME/agents/reviewer/runtime.json"
  [ "$output" = "codex" ]
}

@test "codex runtime has runtime_start function" {
  grep -q 'runtime_start()' "$SAGE_HOME/runtimes/codex.sh"
}

@test "codex runtime has runtime_inject function" {
  grep -q 'runtime_inject()' "$SAGE_HOME/runtimes/codex.sh"
}

@test "codex runtime invokes codex exec" {
  grep -q 'codex exec' "$SAGE_HOME/runtimes/codex.sh"
}

@test "codex runtime supports model flag" {
  grep -q 'model' "$SAGE_HOME/runtimes/codex.sh"
}

@test "codex runtime writes result json" {
  grep -q 'result.json' "$SAGE_HOME/runtimes/codex.sh"
}

@test "codex runtime handles reply_dir" {
  grep -q 'reply_dir' "$SAGE_HOME/runtimes/codex.sh"
}

@test "usage string mentions codex runtime" {
  run "$SAGE" help
  [[ "$output" == *"codex"* ]]
}
