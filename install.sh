#!/bin/bash
# sage — Simple Agent Engine installer
# curl -fsSL https://raw.githubusercontent.com/youwangd/SageCLI/main/install.sh | bash

set -euo pipefail

REPO="youwangd/SageCLI"
BRANCH="main"
INSTALL_DIR="${SAGE_INSTALL_DIR:-$HOME/bin}"
SAGE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/sage"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${GREEN}▸${NC} %s\n" "$1"; }
error() { printf "${RED}✗${NC} %s\n" "$1" >&2; exit 1; }

# Check dependencies
for cmd in bash jq tmux curl; do
  command -v "$cmd" >/dev/null 2>&1 || error "missing dependency: $cmd (install with your package manager)"
done

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download sage
info "Downloading sage from $REPO..."
curl -fsSL "$SAGE_URL" -o "$INSTALL_DIR/sage" || error "failed to download sage"
chmod +x "$INSTALL_DIR/sage"

# Check if install dir is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  SHELL_NAME=$(basename "$SHELL")
  case "$SHELL_NAME" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) RC="$HOME/.bashrc" ;;
    *)    RC="$HOME/.profile" ;;
  esac
  
  echo "" >> "$RC"
  echo "# sage — Simple Agent Engine" >> "$RC"
  echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$RC"
  info "Added $INSTALL_DIR to PATH in $RC"
  info "Run: source $RC (or open a new terminal)"
fi

# Initialize
info "Initializing sage..."
"$INSTALL_DIR/sage" init 2>/dev/null || true

printf "\n${BOLD}⚡ sage installed successfully!${NC}\n\n"
printf "  sage create worker --runtime claude-code\n"
printf "  sage send worker \"Build hello.py\"\n"
printf "  sage peek worker\n\n"
printf "  Docs: https://github.com/$REPO\n\n"
