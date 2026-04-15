#!/usr/bin/env bats
# tests/sage-on-done.bats — tests for send --on-done completion callback

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-$$"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

_make_passing_handler() {
  cat > "$SAGE_HOME/agents/tester/handler.sh" << 'EOF'
#!/bin/bash
handle_message() { echo "ok"; }
EOF
}

_make_failing_handler() {
  cat > "$SAGE_HOME/agents/tester/handler.sh" << 'EOF'
#!/bin/bash
handle_message() { exit 1; }
EOF
}

@test "on-done requires --headless" {
  run sage send tester "echo hi" --on-done "echo done"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--headless"* ]]
}

@test "on-done fires on successful task" {
  _make_passing_handler
  local marker="$SAGE_HOME/done-marker"
  run sage send tester "hello" --headless --on-done "touch $marker"
  [ "$status" -eq 0 ]
  [ -f "$marker" ]
}

@test "on-done fires on failed task" {
  _make_failing_handler
  local marker="$SAGE_HOME/done-marker"
  run sage send tester "hello" --headless --on-done "touch $marker"
  # Task fails but on-done still fires
  [ -f "$marker" ]
}

@test "on-done sets SAGE_DONE_STATUS on success" {
  _make_passing_handler
  local outfile="$SAGE_HOME/done-status"
  run sage send tester "hello" --headless --on-done 'echo $SAGE_DONE_STATUS > '"$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  [[ "$(cat "$outfile")" == "done" ]]
}

@test "on-done sets SAGE_DONE_AGENT env var" {
  _make_passing_handler
  local outfile="$SAGE_HOME/done-agent"
  run sage send tester "hello" --headless --on-done 'echo $SAGE_DONE_AGENT > '"$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  [[ "$(cat "$outfile")" == "tester" ]]
}
