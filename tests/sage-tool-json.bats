#!/usr/bin/env bats
# tests/sage-tool-json.bats — tool ls --json output tests

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/tools"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "tool ls --json emits empty array when no user tools" {
  run ./sage tool ls --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'type')" = "array" ]
  [ "$(echo "$output" | jq -r 'length')" = "0" ]
}

@test "tool ls --json emits array of tools with name and description" {
  echo '#!/bin/bash' > "$SAGE_HOME/tools/hello.sh"
  chmod +x "$SAGE_HOME/tools/hello.sh"
  echo "greets the world" > "$SAGE_HOME/tools/hello.desc"
  run ./sage tool ls --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'length')" = "1" ]
  [ "$(echo "$output" | jq -r '.[0].name')" = "hello" ]
  [ "$(echo "$output" | jq -r '.[0].description')" = "greets the world" ]
}

@test "tool ls --json composes with jq for name extraction" {
  echo '#!/bin/bash' > "$SAGE_HOME/tools/alpha.sh"
  echo '#!/bin/bash' > "$SAGE_HOME/tools/beta.sh"
  chmod +x "$SAGE_HOME/tools/alpha.sh" "$SAGE_HOME/tools/beta.sh"
  run bash -c "./sage tool ls --json | jq -r '.[].name' | sort"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}
