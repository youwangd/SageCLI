#!/usr/bin/env bats
# tests/sage-help-sections.bats — verify sage help shows all command groups

setup() {
  SAGE="$BATS_TEST_DIRNAME/../sage"
  export SAGE_HOME="$(mktemp -d)"
  "$SAGE" init --quiet "$SAGE_HOME" 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "sage help shows MCP SERVERS section" {
  run "$SAGE" help
  [[ "$output" == *"MCP"* ]]
  [[ "$output" == *"mcp add"* ]]
}

@test "sage help shows SKILLS section" {
  run "$SAGE" help
  [[ "$output" == *"SKILL"* ]]
  [[ "$output" == *"skill install"* ]]
}

@test "sage help shows MEMORY section" {
  run "$SAGE" help
  [[ "$output" == *"MEMORY"* ]]
  [[ "$output" == *"memory set"* ]]
}

@test "sage help shows CONTEXT section" {
  run "$SAGE" help
  [[ "$output" == *"context set"* ]]
}

@test "sage help shows ENVIRONMENT section" {
  run "$SAGE" help
  [[ "$output" == *"env set"* ]]
}

@test "sage help shows STATS section" {
  run "$SAGE" help
  [[ "$output" == *"stats"* ]]
  [[ "$output" == *"--cost"* ]]
}

@test "sage help shows ALIASES section" {
  run "$SAGE" help
  [[ "$output" == *"alias set"* ]]
}
