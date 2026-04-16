#!/usr/bin/env bats
# tests/sage-ls-runtime.bats — ls --runtime filters agents by runtime type

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-rt-$$"
  mkdir -p "$SAGE_HOME/agents/alpha" "$SAGE_HOME/agents/beta" "$SAGE_HOME/agents/gamma"
  echo '{"runtime":"claude-code","model":"sonnet-4"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo '{"runtime":"claude-code","model":"opus-4"}' > "$SAGE_HOME/agents/gamma/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ls --runtime filters to matching agents" {
  run ./sage ls --runtime claude-code
  [[ "$output" =~ "alpha" ]]
  [[ "$output" =~ "gamma" ]]
  ! [[ "$output" =~ "beta" ]]
}

@test "ls --runtime with no matches shows nothing" {
  run ./sage ls --runtime ollama
  [[ -z "$output" ]]
}

@test "ls --runtime works with -l" {
  run ./sage ls --runtime bash -l
  [[ "$output" =~ "beta" ]]
  ! [[ "$output" =~ "alpha" ]]
  ! [[ "$output" =~ "gamma" ]]
}

@test "ls --runtime works with --json" {
  run ./sage ls --runtime claude-code --json
  local count
  count=$(echo "$output" | jq 'length')
  [[ "$count" -eq 2 ]]
  echo "$output" | jq -e '.[0].runtime == "claude-code"'
}
