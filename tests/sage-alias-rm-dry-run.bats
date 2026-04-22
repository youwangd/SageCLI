#!/usr/bin/env bats
# tests/sage-alias-rm-dry-run.bats — alias rm --dry-run previews alias without deleting
# Extends the dry-run safety pattern to the alias subsystem.

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"
  printf '{"deploy":"send prod-agent","ship":"send release-agent"}\n' > "$SAGE_HOME/aliases.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "alias rm --dry-run previews alias without deleting" {
  run ./sage alias rm deploy --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would remove"
  echo "$output" | grep -q "deploy"
  # File must still contain both aliases
  grep -q "deploy" "$SAGE_HOME/aliases.json"
  grep -q "ship" "$SAGE_HOME/aliases.json"
}

@test "alias rm --dry-run errors on missing alias" {
  run ./sage alias rm nonexistent --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not found"
}

@test "alias rm without --dry-run still deletes" {
  run ./sage alias rm deploy
  [ "$status" -eq 0 ]
  ! grep -q "deploy" "$SAGE_HOME/aliases.json"
  grep -q "ship" "$SAGE_HOME/aliases.json"
}
