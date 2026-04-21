#!/usr/bin/env bats
# tests/sage-env-rm-dry-run.bats — env rm --dry-run previews key without deleting
# Extends the dry-run safety pattern to the env subsystem.

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/agents/worker"
  printf 'API_KEY=secret123\nDB_URL=postgres://x\n' > "$SAGE_HOME/agents/worker/env"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "env rm --dry-run previews key without deleting" {
  run ./sage env rm worker API_KEY --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would remove API_KEY"
  grep -q "^API_KEY=" "$SAGE_HOME/agents/worker/env"
  grep -q "^DB_URL=" "$SAGE_HOME/agents/worker/env"
}

@test "env rm --dry-run reports missing key" {
  run ./sage env rm worker NOPE --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not set"
}

@test "env rm without --dry-run still deletes" {
  run ./sage env rm worker API_KEY
  [ "$status" -eq 0 ]
  ! grep -q "^API_KEY=" "$SAGE_HOME/agents/worker/env"
  grep -q "^DB_URL=" "$SAGE_HOME/agents/worker/env"
}
