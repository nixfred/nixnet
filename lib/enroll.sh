#!/usr/bin/env bash
# nixnet — enrollment logic
#
# Enrollment is idempotent:
#   - New machine: creates identity, claims it, applies config
#   - Already enrolled: updates claim, re-applies config (self-healing)
#   - Different identity: refuses unless --force
#
# Identity always equals hostname. No --identity flag.
# Roles are gone. Layer model is global → host.

cmd_enroll() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)    force=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    local identity
    identity="$(hostname)"

    # Check yq dependency
    if ! command -v yq &>/dev/null; then
        log_warn "yq is not installed."
        log_warn "  Package management will work, but file placement requires yq."
        log_warn "  Install with: sudo apt-get install -y yq"
        echo ""
        log_info "Continuing without yq — file placement will be skipped."
    fi

    # If already enrolled, make it idempotent
    if is_enrolled; then
        local current
        current="$(current_identity)"
        if [[ "$current" == "$identity" ]]; then
            log_info "Already enrolled as '${identity}' — refreshing..."
            # Update claim (self-healing)
            update_claim "$identity"
            ensure_runtime_dir
            write_local_claim "$identity"

            # Save world path
            local resolved_world
            resolved_world="$(cd "$NIXNET_WORLD" && pwd)"
            write_local_config "WORLD_PATH" "$resolved_world"

            # Re-capture environment state
            log_info "Recapturing environment..."
            capture_environment "$identity"

            # Re-apply config
            log_info "Running apply..."
            cmd_apply

            log_ok "Enrollment refreshed: ${identity}"
            return 0
        fi
        if ! $force; then
            die "Already enrolled as '${current}'. Use --force to re-enroll as '${identity}'."
        fi
    fi

    # Check reclaim safety — warns if identity is claimed by another machine
    local identity_file="${NIXNET_WORLD}/hosts/${identity}/identity.yaml"
    if [[ -f "$identity_file" ]]; then
        if ! check_reclaim_safety "$identity" "$force"; then
            die "Enrollment aborted — identity not reclaimed."
        fi
    fi

    log_info "Enrolling as '${identity}'..."

    # Step 1: Create or claim identity
    if [[ -f "$identity_file" ]]; then
        log_info "Claiming existing identity: ${identity}"
        update_claim "$identity"
    else
        create_identity "$identity"
    fi

    # Step 2: Set up local runtime
    ensure_runtime_dir
    write_local_claim "$identity"

    # Step 3: Save world path for future discovery
    local resolved_world
    resolved_world="$(cd "$NIXNET_WORLD" && pwd)"
    write_local_config "WORLD_PATH" "$resolved_world"
    log_ok "Saved world path: ${resolved_world}"

    # Step 4: Capture environment into world repo (packages + dotfiles)
    capture_environment "$identity"

    # Step 5: Apply configuration
    log_info "Running initial apply..."
    cmd_apply

    # Step 6: Run enrollment hooks
    run_hooks "$identity" "post-enroll"

    log_ok "Enrollment complete: ${identity}"
}
