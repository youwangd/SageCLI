#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-filter-$$"
  mkdir -p "$SAGE_HOME/agents/alpha" "$SAGE_HOME/agents/beta"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ls --running shows only running agents" {
  # Neither agent is running (no .pid), so --running should show nothing
  run ./sage ls --running
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "alpha" ]]
  [[ ! "$output" =~ "beta" ]]
}

@test "ls --stopped shows only stopped agents" {
  run ./sage ls --stopped
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alpha" ]]
  [[ "$output" =~ "beta" ]]
}

@test "ls --running works with --json" {
  run ./sage ls --running --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length == 0'
}

@test "ls --stopped works with --json" {
  run ./sage ls --stopped --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | length == 2'
}
