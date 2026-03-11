#!/usr/bin/env bash
# nixnet — shared functions

# Colors (only when stdout is a terminal)
if [[ -t 1 ]]; then
    _RED='\033[0;31m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _BLUE='\033[0;34m'
    _BOLD='\033[1m'
    _RESET='\033[0m'
else
    _RED='' _GREEN='' _YELLOW='' _BLUE='' _BOLD='' _RESET=''
fi

log_info()  { echo -e "${_BLUE}[nixnet]${_RESET} $*"; }
log_ok()    { echo -e "${_GREEN}[nixnet]${_RESET} $*"; }
log_warn()  { echo -e "${_YELLOW}[nixnet]${_RESET} $*" >&2; }
log_error() { echo -e "${_RED}[nixnet]${_RESET} $*" >&2; }

die() { log_error "$@"; exit 1; }

# Check if a command exists
require_cmd() {
    command -v "$1" &>/dev/null || die "Required command not found: $1"
}

# Generate a stable machine ID from hardware facts
# Uses /etc/machine-id (systemd) as the primary source
get_machine_id() {
    if [[ -f /etc/machine-id ]]; then
        cat /etc/machine-id
    else
        die "Cannot determine machine ID: /etc/machine-id not found"
    fi
}

# Get basic machine facts as a simple report
get_machine_facts() {
    local hostname os kernel arch
    hostname="$(hostname)"
    os="$(lsb_release -ds 2>/dev/null || echo "unknown")"
    kernel="$(uname -r)"
    arch="$(uname -m)"
    echo "hostname=${hostname}"
    echo "os=${os}"
    echo "kernel=${kernel}"
    echo "arch=${arch}"
}

# Read a YAML field using yq (simple key: value extraction)
# Falls back to grep/sed for environments without yq
yaml_read() {
    local file="$1" key="$2"
    if command -v yq &>/dev/null; then
        yq -r ".${key} // empty" "$file" 2>/dev/null
    else
        # Fallback: simple top-level key extraction (no nesting)
        grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/^"\(.*\)"$/\1/'
    fi
}

# Read a YAML list into a bash array (one item per line)
yaml_read_list() {
    local file="$1" key="$2"
    if command -v yq &>/dev/null; then
        yq -r ".${key}[]? // empty" "$file" 2>/dev/null
    else
        # Fallback: read indented list items under key
        sed -n "/^${key}:/,/^[^ ]/p" "$file" | grep '^ *- ' | sed 's/^ *- //'
    fi
}

# Ensure local runtime directory exists
ensure_runtime_dir() {
    mkdir -p "${NIXNET_LOCAL}"/{state,cache/resolved,log,adopted}
}

# Check if this machine is enrolled
is_enrolled() {
    [[ -f "${NIXNET_LOCAL}/identity.json" ]]
}

# Read current identity name from local claim
current_identity() {
    if is_enrolled; then
        # Simple JSON field extraction without jq dependency
        if command -v jq &>/dev/null; then
            jq -r '.name' "${NIXNET_LOCAL}/identity.json"
        else
            grep '"name"' "${NIXNET_LOCAL}/identity.json" | sed 's/.*: *"\(.*\)".*/\1/'
        fi
    else
        echo ""
    fi
}

# Timestamp in ISO 8601
now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Read a value from the local nixnet config file (key=value format)
# Usage: read_local_config KEY
read_local_config() {
    local key="$1"
    local config="${NIXNET_LOCAL}/config"
    [[ -f "$config" ]] || return 1
    grep "^${key}=" "$config" 2>/dev/null | head -1 | cut -d= -f2-
}

# Write a value to the local nixnet config file (key=value format)
# Creates the file and parent dirs if needed. Updates existing key or appends.
# Usage: write_local_config KEY VALUE
write_local_config() {
    local key="$1" value="$2"
    local config="${NIXNET_LOCAL}/config"
    mkdir -p "$(dirname "$config")"
    if [[ -f "$config" ]] && grep -q "^${key}=" "$config" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$config"
    else
        echo "${key}=${value}" >> "$config"
    fi
}
