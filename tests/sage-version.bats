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

@test "sage upgrade shows help text" {
  export SAGE_HOME="$BATS_TMPDIR/sage-test-$$"
  mkdir -p "$SAGE_HOME"
  # --check should compare versions without actually upgrading
  run "$SAGE" upgrade --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage"* ]]
  rm -rf "$SAGE_HOME"
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
