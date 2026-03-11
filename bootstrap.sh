#!/usr/bin/env bash
# nixnet bootstrap — one command to enroll any Ubuntu machine
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/nixfred/nixnet/main/bootstrap.sh | bash -s -- <world-repo-url>
#
# Example:
#   curl -sL https://raw.githubusercontent.com/nixfred/nixnet/main/bootstrap.sh | bash -s -- git@github.com:nixfred/nixnet-world.git
#
# What this does:
#   1. Installs git and yq if missing
#   2. Clones the nixnet engine to ~/Projects/nixnet/
#   3. Clones your private world repo to ~/Projects/nixnet-world/
#   4. Runs nixnet enroll (identity = hostname, always)
#
# Re-running is safe — it updates code and refreshes enrollment.

set -euo pipefail

# Colors
if [[ -t 1 ]]; then
    _GREEN='\033[0;32m' _YELLOW='\033[0;33m' _RED='\033[0;31m'
    _BLUE='\033[0;34m' _BOLD='\033[1m' _RESET='\033[0m'
else
    _GREEN='' _YELLOW='' _RED='' _BLUE='' _BOLD='' _RESET=''
fi

info()  { echo -e "${_BLUE}[nixnet]${_RESET} $*"; }
ok()    { echo -e "${_GREEN}[nixnet]${_RESET} $*"; }
warn()  { echo -e "${_YELLOW}[nixnet]${_RESET} $*" >&2; }
fail()  { echo -e "${_RED}[nixnet]${_RESET} $*" >&2; exit 1; }

# ── Parse arguments ──────────────────────────────────────────────

WORLD_URL="${1:-}"
ENGINE_URL="https://github.com/nixfred/nixnet.git"
INSTALL_DIR="${HOME}/Projects"
ENGINE_DIR="${INSTALL_DIR}/nixnet"
WORLD_DIR="${INSTALL_DIR}/nixnet-world"

if [[ -z "$WORLD_URL" ]]; then
    # Check if we're already enrolled — re-run mode
    if [[ -f "${HOME}/.nixnet/config" ]]; then
        WORLD_DIR="$(grep '^WORLD_PATH=' "${HOME}/.nixnet/config" 2>/dev/null | cut -d= -f2-)"
        if [[ -n "$WORLD_DIR" && -d "$WORLD_DIR" ]]; then
            info "Re-run detected — using saved world path: ${WORLD_DIR}"
        else
            fail "Usage: bootstrap.sh <world-repo-url>"
        fi
    else
        fail "Usage: bootstrap.sh <world-repo-url>"
    fi
fi

echo -e "${_BOLD}nixnet bootstrap${_RESET}"
echo "---"
info "Identity:  $(hostname)"
info "Engine:    ${ENGINE_URL}"
info "World:     ${WORLD_URL:-${WORLD_DIR}}"
echo ""

# ── Step 1: Install prerequisites ────────────────────────────────

info "step 1/4: checking prerequisites..."

install_if_missing() {
    local cmd="$1" pkg="${2:-$1}"
    if ! command -v "$cmd" &>/dev/null; then
        info "installing ${pkg}..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq "$pkg"
        ok "${pkg} installed"
    else
        ok "${cmd} already available"
    fi
}

install_if_missing git
install_if_missing yq

# ── Step 2: Clone or update engine ───────────────────────────────

info "step 2/4: setting up engine..."

mkdir -p "$INSTALL_DIR"

if [[ -d "${ENGINE_DIR}/.git" ]]; then
    info "engine exists — pulling latest..."
    git -C "$ENGINE_DIR" pull --rebase --quiet
    ok "engine updated"
else
    info "cloning engine..."
    git clone --quiet "$ENGINE_URL" "$ENGINE_DIR"
    ok "engine cloned to ${ENGINE_DIR}"
fi

# ── Step 3: Clone or update world ────────────────────────────────

info "step 3/4: setting up world..."

if [[ -d "${WORLD_DIR}/.git" ]]; then
    info "world exists — pulling latest..."
    git -C "$WORLD_DIR" pull --rebase --quiet
    ok "world updated"
elif [[ -n "$WORLD_URL" ]]; then
    info "cloning world..."
    git clone --quiet "$WORLD_URL" "$WORLD_DIR"
    ok "world cloned to ${WORLD_DIR}"
fi

# ── Step 4: Enroll ───────────────────────────────────────────────

info "step 4/4: enrolling..."

export NIXNET_WORLD="$WORLD_DIR"
"${ENGINE_DIR}/bin/nixnet" enroll

echo ""
ok "bootstrap complete — $(hostname) is enrolled in nixnet"
echo ""
info "Commands:"
info "  ${ENGINE_DIR}/bin/nixnet status"
info "  ${ENGINE_DIR}/bin/nixnet doctor"
info "  ${ENGINE_DIR}/bin/nixnet sync"
info "  ${ENGINE_DIR}/bin/nixnet apply"
