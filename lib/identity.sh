#!/usr/bin/env bash
# nixnet — host identity operations

# Show identity details for current or named host
cmd_identity() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        is_enrolled || die "Not enrolled. Run: nixnet enroll"
        name="$(current_identity)"
    fi

    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    [[ -f "$identity_file" ]] || die "No identity found: ${name}"

    echo -e "${_BOLD}Host Identity: ${name}${_RESET}"
    echo "---"
    cat "$identity_file"
}

# Create a new host identity manifest
create_identity() {
    local name="$1"
    local host_dir="${NIXNET_WORLD}/hosts/${name}"
    local identity_file="${host_dir}/identity.yaml"

    if [[ -f "$identity_file" ]]; then
        log_info "Identity '${name}' already exists — claiming it"
        return 0
    fi

    mkdir -p "${host_dir}"/{files,hooks}

    local machine_id hostname
    machine_id="$(get_machine_id)"
    hostname="$(hostname)"

    cat > "$identity_file" <<EOF
name: ${name}
lifecycle: active
description: ""
tags: []
machine_class: ""
created: $(now_iso)

claim:
  machine_id: ${machine_id}
  hostname: ${hostname}
  claimed_at: $(now_iso)
  os: $(lsb_release -ds 2>/dev/null || echo "unknown")
  kernel: $(uname -r)
EOF

    # Create empty layer files so the structure is complete
    [[ -f "${host_dir}/packages.yaml" ]] || echo "packages: []" > "${host_dir}/packages.yaml"

    log_ok "Created identity: ${name}"
}

# Check if an identity is currently claimed by a different machine
# Returns 0 if safe to proceed, 1 if claimed by another and not forced
check_reclaim_safety() {
    local name="$1" force="$2"
    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"

    [[ -f "$identity_file" ]] || return 0  # new identity, no conflict

    local existing_machine_id=""
    local existing_hostname=""
    local existing_claimed_at=""
    local existing_lifecycle=""

    if command -v yq &>/dev/null; then
        existing_machine_id="$(yq -r '.claim.machine_id // empty' "$identity_file")"
        existing_hostname="$(yq -r '.claim.hostname // empty' "$identity_file")"
        existing_claimed_at="$(yq -r '.claim.claimed_at // empty' "$identity_file")"
        existing_lifecycle="$(yq -r '.lifecycle // empty' "$identity_file")"
    else
        existing_machine_id="$(yaml_read "$identity_file" "machine_id" 2>/dev/null || true)"
        existing_hostname="$(grep 'hostname:' "$identity_file" | head -1 | sed 's/.*: *//')"
        existing_lifecycle="$(yaml_read "$identity_file" "lifecycle")"
    fi

    # No existing claim or empty claim — safe
    [[ -n "$existing_machine_id" ]] || return 0

    local my_machine_id
    my_machine_id="$(get_machine_id)"

    # Same machine — safe (re-enrollment)
    [[ "$existing_machine_id" != "$my_machine_id" ]] || return 0

    # Different machine holds this identity
    log_warn "Identity '${name}' is currently claimed by another machine:"
    log_warn "  Machine ID: ${existing_machine_id}"
    log_warn "  Hostname:   ${existing_hostname}"
    log_warn "  Claimed at: ${existing_claimed_at}"
    log_warn "  Lifecycle:  ${existing_lifecycle}"
    echo ""

    if [[ "$force" == "true" ]]; then
        log_info "Reclaiming identity (--force specified)"
        return 0
    fi

    # Interactive confirmation
    if [[ -t 0 ]]; then
        echo -n "Reclaim this identity? The previous claim will be archived. [y/N] "
        local answer
        read -r answer
        case "$answer" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    else
        die "Identity '${name}' is claimed by another machine. Use --force to reclaim non-interactively."
    fi
}

# Save current claim to history before overwriting
save_claim_history() {
    local name="$1"
    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    local history_file="${NIXNET_WORLD}/hosts/${name}/claim-history.txt"

    [[ -f "$identity_file" ]] || return 0

    local existing_machine_id=""
    local existing_hostname=""
    local existing_claimed_at=""

    if command -v yq &>/dev/null; then
        existing_machine_id="$(yq -r '.claim.machine_id // empty' "$identity_file")"
        existing_hostname="$(yq -r '.claim.hostname // empty' "$identity_file")"
        existing_claimed_at="$(yq -r '.claim.claimed_at // empty' "$identity_file")"
    fi

    [[ -n "$existing_machine_id" ]] || return 0

    echo "$(now_iso) | replaced | machine_id=${existing_machine_id} hostname=${existing_hostname} claimed_at=${existing_claimed_at}" \
        >> "$history_file"

    log_info "Previous claim archived to claim-history.txt"
}

# Update the claim block when a machine claims an existing identity
update_claim() {
    local name="$1"
    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    [[ -f "$identity_file" ]] || die "Identity not found: ${name}"

    # Save old claim before overwriting
    save_claim_history "$name"

    local machine_id hostname
    machine_id="$(get_machine_id)"
    hostname="$(hostname)"

    # Update claim fields and set lifecycle to active
    if command -v yq &>/dev/null; then
        yq -yi ".claim.machine_id = \"${machine_id}\" |
               .claim.hostname = \"${hostname}\" |
               .claim.claimed_at = \"$(now_iso)\" |
               .claim.os = \"$(lsb_release -ds 2>/dev/null || echo unknown)\" |
               .claim.kernel = \"$(uname -r)\" |
               .lifecycle = \"active\"" "$identity_file"
    else
        log_warn "yq not available — claim update requires manual edit of ${identity_file}"
    fi

    log_ok "Updated claim for identity: ${name}"
}

# Write the local identity claim file
write_local_claim() {
    local name="$1"
    local machine_id
    machine_id="$(get_machine_id)"

    ensure_runtime_dir

    cat > "${NIXNET_LOCAL}/identity.json" <<EOF
{
  "name": "${name}",
  "machine_id": "${machine_id}",
  "enrolled_at": "$(now_iso)",
  "nixnet_version": "${NIXNET_VERSION}"
}
EOF
}
