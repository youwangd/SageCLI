#!/usr/bin/env bats
# tests/sage-tool-count.bats — tool ls --count prints plain integer

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"/{agents,runtimes,tools}
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'EOF'
runtime_start() { :; }
runtime_inject() { echo "ok"; }
EOF
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "tool ls --count prints 0 when no tools registered" {
  rm -f "$SAGE_HOME/tools"/*.sh 2>/dev/null || true
  run sage tool ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "tool ls --count prints integer count of registered tools" {
  echo '#!/bin/bash' > "$SAGE_HOME/tools/alpha.sh"
  echo '#!/bin/bash' > "$SAGE_HOME/tools/beta.sh"
  echo '#!/bin/bash' > "$SAGE_HOME/tools/gamma.sh"
  run sage tool ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "tool ls --count output is scriptable (pure digits)" {
  echo '#!/bin/bash' > "$SAGE_HOME/tools/one.sh"
  run sage tool ls --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}
