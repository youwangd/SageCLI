#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-headless-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- send --headless ---

@test "send --headless runs task without tmux" {
  run "$SAGE" send worker "echo hello" --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "send --headless exits 1 on handler failure" {
  # Create a handler that fails
  cat > "$SAGE_HOME/agents/worker/handler.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$SAGE_HOME/agents/worker/handler.sh"
  run "$SAGE" send worker "do something" --headless
  [ "$status" -eq 1 ]
}

@test "send --headless --json outputs JSON result" {
  run "$SAGE" send worker "echo hello" --headless --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status' >/dev/null 2>&1
}

@test "send --headless requires agent name" {
  run "$SAGE" send --headless
  [ "$status" -eq 1 ]
}

@test "send --headless rejects non-existent agent" {
  run "$SAGE" send ghost "test" --headless
  [ "$status" -eq 1 ]
}
