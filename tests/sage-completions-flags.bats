#!/usr/bin/env bats
# tests/sage-completions-flags.bats — completions include flags added in cycles 139-142

@test "bash completions mention --failed flag" {
  run "$BATS_TEST_DIRNAME/../sage" completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--failed"* ]]
}

@test "bash completions mention --graceful flag" {
  run "$BATS_TEST_DIRNAME/../sage" completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--graceful"* ]]
}

@test "bash completions offer ls flags (--running --stopped --failed --json --tree -q)" {
  run "$BATS_TEST_DIRNAME/../sage" completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--running"* ]]
  [[ "$output" == *"--stopped"* ]]
  [[ "$output" == *"--runtime"* ]]
  [[ "$output" == *"--tree"* ]]
}

@test "bash completions offer logs flags (--all --failed --grep --tail --since -f)" {
  run "$BATS_TEST_DIRNAME/../sage" completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--grep"* ]]
  [[ "$output" == *"--tail"* ]]
  [[ "$output" == *"--since"* ]]
}

@test "zsh completions mention --failed flag" {
  run "$BATS_TEST_DIRNAME/../sage" completions zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--failed"* ]]
}
