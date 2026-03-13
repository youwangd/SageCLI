#!/bin/bash
# Runtime: bash handler

runtime_start() {
  local agent_dir="$1" name="$2"
  for tool in "$SAGE_HOME/tools"/*.sh; do
    [[ -f "$tool" ]] && source "$tool"
  done
  source "$agent_dir/handler.sh"
}

runtime_inject() {
  local name="$1" msg="$2"
  handle_message "$msg"
}
