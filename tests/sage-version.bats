#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

@test "sage --version prints version" {
  run "$SAGE" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^sage\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "sage -v prints version" {
  run "$SAGE" -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^sage\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "sage version prints version" {
  run "$SAGE" version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^sage\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "sage upgrade --check runs without error when network available" {
  # This test verifies the command exists and parses --check flag
  # It may fail if no network, so we just check it doesn't die with "unknown command"
  run "$SAGE" upgrade --check
  # Either succeeds (network ok) or fails with curl error — not "unknown command"
  [[ "$output" != *"unknown command"* ]]
}

@test "sage help includes upgrade command" {
  run "$SAGE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"upgrade"* ]]
}

@test "sage help includes version flag" {
  run "$SAGE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--version"* ]]
}
