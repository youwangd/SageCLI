#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-completions-test-$$"
  "$SAGE" init 2>/dev/null
  "$SAGE" create alpha --runtime bash 2>/dev/null
  "$SAGE" create beta --runtime bash 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "completions bash outputs valid bash function" {
  run "$SAGE" completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"_sage_completions"* ]]
  [[ "$output" == *"COMPREPLY"* ]]
  [[ "$output" == *"complete -F"* ]]
}

@test "completions bash includes all subcommands" {
  run "$SAGE" completions bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"create"* ]]
  [[ "$output" == *"send"* ]]
  [[ "$output" == *"rename"* ]]
  [[ "$output" == *"completions"* ]]
}

@test "completions zsh outputs valid zsh function" {
  run "$SAGE" completions zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"compdef"* ]]
  [[ "$output" == *"_sage"* ]]
}

@test "completions without shell arg shows usage" {
  run "$SAGE" completions
  [ "$status" -ne 0 ]
}

@test "completions with invalid shell fails" {
  run "$SAGE" completions fish
  [ "$status" -ne 0 ]
}
