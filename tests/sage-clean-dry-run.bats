#!/usr/bin/env bats
# tests/sage-clean-dry-run.bats — clean --dry-run previews without deleting

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-home"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --quiet 2>/dev/null || true
  # Create a fake agent with a stale pid file
  mkdir -p "$SAGE_HOME/agents/stale-agent"
  echo '{"name":"stale-agent","runtime":"bash"}' > "$SAGE_HOME/agents/stale-agent/agent.json"
  echo "99999999" > "$SAGE_HOME/agents/stale-agent/.pid"
  # Create old reply files
  mkdir -p "$SAGE_HOME/agents/stale-agent/replies"
  touch -t 202501010000 "$SAGE_HOME/agents/stale-agent/replies/old.json"
}

@test "clean --dry-run shows what would be cleaned" {
  run sage clean --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]] || [[ "$output" == *"would"* ]]
}

@test "clean --dry-run does not delete files" {
  run sage clean --dry-run
  [ "$status" -eq 0 ]
  # Stale pid should still exist
  [ -f "$SAGE_HOME/agents/stale-agent/.pid" ]
}

@test "clean without --dry-run deletes stale files" {
  run sage clean
  [ "$status" -eq 0 ]
  # Stale pid should be gone
  [ ! -f "$SAGE_HOME/agents/stale-agent/.pid" ]
}

@test "clean --dry-run shows count" {
  run sage clean --dry-run
  [ "$status" -eq 0 ]
  # Should mention a number
  [[ "$output" =~ [0-9] ]]
}
