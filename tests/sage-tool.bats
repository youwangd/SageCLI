#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/tools"
  # Create a test tool
  echo '#!/bin/bash' > "$SAGE_HOME/tools/hello.sh"
  echo 'echo hello' >> "$SAGE_HOME/tools/hello.sh"
  chmod +x "$SAGE_HOME/tools/hello.sh"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "tool ls lists registered tools" {
  run ./sage tool ls
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hello"
}

@test "tool add registers a new tool" {
  local tmp=$(mktemp)
  echo '#!/bin/bash' > "$tmp"
  echo 'echo world' >> "$tmp"
  run ./sage tool add mytool "$tmp"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/tools/mytool.sh" ]
  rm -f "$tmp"
}

@test "tool rm removes a registered tool" {
  run ./sage tool rm hello
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/tools/hello.sh" ]
}

@test "tool rm fails for nonexistent tool" {
  run ./sage tool rm nonexistent
  [ "$status" -ne 0 ]
}

@test "tool show displays tool content" {
  run ./sage tool show hello
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "echo hello"
}

@test "tool show fails for nonexistent tool" {
  run ./sage tool show nonexistent
  [ "$status" -ne 0 ]
}

@test "tool run executes a registered tool" {
  run ./sage tool run hello
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hello"
}

@test "tool run forwards arguments to tool" {
  echo '#!/bin/bash' > "$SAGE_HOME/tools/greet.sh"
  echo 'echo "hi $1"' >> "$SAGE_HOME/tools/greet.sh"
  chmod +x "$SAGE_HOME/tools/greet.sh"
  run ./sage tool run greet world
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hi world"
}

@test "tool run fails for nonexistent tool" {
  run ./sage tool run nonexistent
  [ "$status" -ne 0 ]
}