#!/usr/bin/env bats
# tests/sage-tool-dry-run.bats — tool rm --dry-run previews path without deleting
# Mirrors tests/sage-skill-dry-run.bats for the sibling tool subsystem.

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/tools"
  echo '#!/bin/bash' > "$SAGE_HOME/tools/hello.sh"
  echo 'echo hello' >> "$SAGE_HOME/tools/hello.sh"
  chmod +x "$SAGE_HOME/tools/hello.sh"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "tool rm --dry-run previews without deleting" {
  run ./sage tool rm hello --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would remove tool"
  echo "$output" | grep -q "hello"
  [ -f "$SAGE_HOME/tools/hello.sh" ]
}

@test "tool rm --dry-run shows desc path when desc file exists" {
  echo "A greeting tool" > "$SAGE_HOME/tools/hello.desc"
  run ./sage tool rm hello --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "desc:"
  [ -f "$SAGE_HOME/tools/hello.sh" ]
  [ -f "$SAGE_HOME/tools/hello.desc" ]
}

@test "tool rm --dry-run fails for nonexistent tool" {
  run ./sage tool rm nonexistent --dry-run
  [ "$status" -ne 0 ]
}
