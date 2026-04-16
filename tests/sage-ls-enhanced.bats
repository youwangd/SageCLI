#!/usr/bin/env bats
# tests/sage-ls-enhanced.bats — ls -l shows MODEL and LAST_ACTIVE columns

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-enh-$$"
  mkdir -p "$SAGE_HOME/agents/alpha/results" "$SAGE_HOME/agents/beta"
  echo '{"runtime":"claude-code","model":"sonnet-4"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"
  # Create a status file for alpha with a known timestamp
  echo '{"finished_at":"2026-04-16T10:30:00Z"}' > "$SAGE_HOME/agents/alpha/results/001.status.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ls -l shows MODEL column" {
  run ./sage ls -l
  [ "$status" -eq 0 ]
  [[ "$output" =~ "MODEL" ]]
  [[ "$output" =~ "sonnet-4" ]]
  [[ "$output" =~ "default" ]]
}

@test "ls -l shows LAST_ACTIVE column" {
  run ./sage ls -l
  [ "$status" -eq 0 ]
  [[ "$output" =~ "LAST_ACTIVE" ]]
  [[ "$output" =~ "2026-04-16" ]]
}

@test "ls -l shows never for agent with no tasks" {
  run ./sage ls -l
  [ "$status" -eq 0 ]
  [[ "$output" =~ "never" ]]
}

@test "ls --json includes model and last_active fields" {
  run ./sage ls --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].model'
  echo "$output" | jq -e '.[0].last_active'
}
