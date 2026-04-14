#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-stdin-$$"
  sage init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "send reads message from stdin when piped" {
  sage create worker stdin-test --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/stdin-test"
  cat > "$agent_dir/handler.sh" << 'HANDLER'
handle_message() { echo "got: $1"; }
HANDLER
  run bash -c 'echo "hello from pipe" | sage send stdin-test --headless'
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello from pipe"* ]]
}

@test "send prefers positional message over stdin" {
  sage create worker stdin-pos --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/stdin-pos"
  cat > "$agent_dir/handler.sh" << 'HANDLER'
handle_message() { echo "got: $1"; }
HANDLER
  run bash -c 'echo "from stdin" | sage send stdin-pos "from args" --headless'
  [ "$status" -eq 0 ]
  [[ "$output" == *"from args"* ]]
}

@test "send reads multiline stdin" {
  sage create worker stdin-multi --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/stdin-multi"
  cat > "$agent_dir/handler.sh" << 'HANDLER'
handle_message() { echo "got: $1"; }
HANDLER
  run bash -c 'printf "line1\nline2\nline3" | sage send stdin-multi --headless'
  [ "$status" -eq 0 ]
  [[ "$output" == *"line1"* ]]
  [[ "$output" == *"line3"* ]]
}

@test "send with empty stdin and no message shows error" {
  sage create worker stdin-empty --runtime bash 2>/dev/null
  run bash -c 'echo -n "" | sage send stdin-empty --headless'
  [ "$status" -ne 0 ]
}

@test "send stdin works with @file taking precedence" {
  sage create worker stdin-file --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/stdin-file"
  cat > "$agent_dir/handler.sh" << 'HANDLER'
handle_message() { echo "got: $1"; }
HANDLER
  echo "from file" > "$BATS_TEST_TMPDIR/msg.txt"
  run bash -c 'echo "from stdin" | sage send stdin-file "@'"$BATS_TEST_TMPDIR"'/msg.txt" --headless'
  [ "$status" -eq 0 ]
  [[ "$output" == *"from file"* ]]
}
