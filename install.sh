#!/usr/bin/env bash
# ==============================================================================
# Installer / Validator for omarchy-theme-transitions
# Packages transition logic as a documented reference port.
# Does NOT replace core Omarchy shell files automatically.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
DRY_RUN=0

for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

run_cmd() {
  if (( DRY_RUN )); then echo "[DRY-RUN] $*"; else "$@"; fi
}

check_deps() {
  echo "Checking requirements for omarchy-theme-transitions..."
  local missing=0
  if command -v quickshell >/dev/null 2>&1; then
    echo "  [OK] Quickshell is installed ($(quickshell --version 2>/dev/null || echo 'active'))"
  else
    echo "  [FAIL] Quickshell is required."
    missing=1
  fi
  if [[ -x /usr/lib/qt6/bin/qsb ]]; then
    echo "  [OK] Qt Shader Baker (qsb) is available"
  else
    echo "  [WARN] /usr/lib/qt6/bin/qsb not found (qt6-shadertools package)"
  fi
  return $missing
}

do_install() {
  check_deps
  echo "Installing CLI utility omarchy-theme-transition to $BIN_DIR..."
  run_cmd mkdir -p "$BIN_DIR"
  if [[ -f "$SCRIPT_DIR/bin/omarchy-theme-transition" ]]; then
    run_cmd cp "$SCRIPT_DIR/bin/omarchy-theme-transition" "$BIN_DIR/"
    run_cmd chmod +x "$BIN_DIR/omarchy-theme-transition"
  fi

  echo ""
  echo "NOTE: Theme transitions modify Quickshell background compositing."
  echo "To prevent overwriting upstream Omarchy shell updates, files are packaged as a reference port."
  echo "See docs/MANUAL-INSTALLATION.md for instructions on applying the reference port to your shell."
}

do_status() {
  echo "=== Theme Transitions Status ==="
  if command -v omarchy-theme-transition >/dev/null 2>&1; then
    echo -n "  Active transition mode: "
    omarchy-theme-transition get 2>/dev/null || echo "not set"
  else
    echo "  CLI utility omarchy-theme-transition is not installed."
  fi
}

do_uninstall() {
  echo "Removing CLI utility omarchy-theme-transition..."
  if [[ -f "$BIN_DIR/omarchy-theme-transition" ]]; then
    run_cmd rm -f "$BIN_DIR/omarchy-theme-transition"
  fi
  echo "CLI utility uninstalled."
}

case "${1:-check}" in
  check) check_deps ;;
  install) do_install ;;
  update) do_install ;;
  status) do_status ;;
  uninstall) do_uninstall ;;
  *)
    echo "Usage: $0 {check|install|update|status|uninstall} [--dry-run]"
    exit 1
    ;;
esac
