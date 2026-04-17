#!/usr/bin/env bats
# tests/sage-send-env.bats — send --env KEY=VAL passes ad-hoc env vars to task

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-env-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create tester --runtime bash >/dev/null 2>&1
  # Replace handler to print env vars
  cat > "$SAGE_HOME/agents/tester/handler.sh" << 'EOF'
#!/bin/bash
handle_message() {
  local msg="$1"
  local text=$(echo "$msg" | jq -r '.payload.text')
  eval "$text"
}
EOF
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "send --env injects env var into headless task" {
  run "$SAGE" send tester 'echo $MY_VAR' --headless --env MY_VAR=hello123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hello123"
}

@test "send --env supports multiple vars" {
  run "$SAGE" send tester 'echo ${A}_${B}' --headless --env A=foo --env B=bar
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "foo_bar"
}

@test "send --env does not persist to agent env file" {
  run "$SAGE" send tester 'echo $TEMP_VAR' --headless --env TEMP_VAR=ephemeral
  [ "$status" -eq 0 ]
  # Agent's persistent env file should NOT contain TEMP_VAR
  if [ -f "$SAGE_HOME/agents/tester/env" ]; then
    ! grep -q "TEMP_VAR" "$SAGE_HOME/agents/tester/env"
  fi
}

@test "send --env rejects invalid format" {
  run "$SAGE" send tester 'echo hi' --headless --env "BADFORMAT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "invalid.*env\|KEY=VAL"
}
