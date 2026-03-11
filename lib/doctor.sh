#!/usr/bin/env bash
# nixnet — health checks

cmd_doctor() {
    local checks=0 passed=0 warned=0 failed=0

    echo -e "${_BOLD}nixnet doctor${_RESET}"
    echo "---"

    # Check 1: Identity claimed
    checks=$((checks + 1))
    if is_enrolled; then
        local name
        name="$(current_identity)"
        doctor_pass "Identity claimed: ${name}"
        passed=$((passed + 1))
    else
        doctor_fail "No identity claimed — run: nixnet enroll"
        failed=$((failed + 1))
        doctor_summary $checks $passed $warned $failed
        return 1
    fi

    # Check 2: Runtime directory structure
    checks=$((checks + 1))
    local missing_dirs=()
    for d in state cache/resolved log; do
        [[ -d "${NIXNET_LOCAL}/${d}" ]] || missing_dirs+=("$d")
    done
    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        doctor_pass "Runtime directory intact"
        passed=$((passed + 1))
    else
        doctor_warn "Missing runtime dirs: ${missing_dirs[*]}"
        warned=$((warned + 1))
    fi

    # Check 3: World directory reachable
    checks=$((checks + 1))
    if [[ -d "${NIXNET_WORLD}" ]]; then
        doctor_pass "World directory: ${NIXNET_WORLD}"
        passed=$((passed + 1))
    else
        doctor_fail "World directory not found: ${NIXNET_WORLD}"
        failed=$((failed + 1))
    fi

    # Check 4: Identity file exists in world
    checks=$((checks + 1))
    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    if [[ -f "$identity_file" ]]; then
        doctor_pass "Identity file exists: ${identity_file}"
        passed=$((passed + 1))
    else
        doctor_fail "Identity file missing: ${identity_file}"
        failed=$((failed + 1))
    fi

    # Check 5: Global layer exists
    checks=$((checks + 1))
    if [[ -d "${NIXNET_WORLD}/global" ]]; then
        doctor_pass "Global layer exists"
        passed=$((passed + 1))
    else
        doctor_fail "Global layer missing: ${NIXNET_WORLD}/global"
        failed=$((failed + 1))
    fi

    # Check 6: Last apply recorded
    checks=$((checks + 1))
    local last_apply="${NIXNET_LOCAL}/state/last-apply.json"
    if [[ -f "$last_apply" ]]; then
        local applied_at
        if command -v jq &>/dev/null; then
            applied_at="$(jq -r '.applied_at' "$last_apply")"
        else
            applied_at="$(grep 'applied_at' "$last_apply" | sed 's/.*: *"\(.*\)".*/\1/')"
        fi
        doctor_pass "Last apply: ${applied_at}"
        passed=$((passed + 1))
    else
        doctor_warn "No apply recorded yet — run: nixnet apply"
        warned=$((warned + 1))
    fi

    # Check 7: yq dependency
    checks=$((checks + 1))
    if command -v yq &>/dev/null; then
        local yq_version
        yq_version="$(yq --version 2>&1 | head -1)"
        doctor_pass "yq available: ${yq_version}"
        passed=$((passed + 1))
    else
        doctor_warn "yq not installed — file placement will not work"
        doctor_warn "  Install: sudo apt-get install -y yq"
        warned=$((warned + 1))
    fi

    # Check 8: Managed symlinks intact
    checks=$((checks + 1))
    local broken_links=0
    if [[ -f "${NIXNET_LOCAL}/cache/resolved/files.list" ]]; then
        while IFS= read -r layer_file; do
            if command -v yq &>/dev/null && [[ -f "$layer_file" ]]; then
                local count
                count="$(yq '.files | length' "$layer_file" 2>/dev/null)" || continue
                for ((i=0; i<count; i++)); do
                    local dest method
                    dest="$(yq -r ".files[$i].dest" "$layer_file")"
                    method="$(yq -r ".files[$i].method // \"auto\"" "$layer_file")"
                    dest="${dest/#\~/$HOME}"
                    if [[ "$method" == "symlink" || ("$method" == "auto" && "$dest" != /etc/* && "$dest" != /usr/*) ]]; then
                        if [[ -L "$dest" && ! -e "$dest" ]]; then
                            broken_links=$((broken_links + 1))
                            doctor_warn "Broken symlink: ${dest}"
                        fi
                    fi
                done
            fi
        done < "${NIXNET_LOCAL}/cache/resolved/files.list"
    fi
    if [[ $broken_links -eq 0 ]]; then
        doctor_pass "Managed symlinks intact"
        passed=$((passed + 1))
    else
        warned=$((warned + 1))
    fi

    echo "---"
    doctor_summary $checks $passed $warned $failed
    [[ $failed -eq 0 ]] && return 0 || return 1
}

doctor_pass() { echo -e "  ${_GREEN}✓${_RESET} $*"; }
doctor_warn() { echo -e "  ${_YELLOW}⚠${_RESET} $*"; }
doctor_fail() { echo -e "  ${_RED}✗${_RESET} $*"; }

doctor_summary() {
    local checks=$1 passed=$2 warned=$3 failed=$4
    echo -e "${_BOLD}${checks} checks:${_RESET} ${_GREEN}${passed} passed${_RESET}, ${_YELLOW}${warned} warnings${_RESET}, ${_RED}${failed} failed${_RESET}"
}
