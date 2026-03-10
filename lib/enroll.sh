#!/usr/bin/env bash
# nixnet — enrollment logic

cmd_enroll() {
    local identity="" role="" adopt=false force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --identity) identity="$2"; shift 2 ;;
            --role)     role="$2"; shift 2 ;;
            --adopt)    adopt=true; shift ;;
            --force)    force=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    [[ -n "$identity" ]] || die "Required: --identity NAME"
    [[ -n "$role" ]]     || die "Required: --role ROLE"

    # Check yq dependency
    if ! command -v yq &>/dev/null; then
        log_warn "yq is not installed."
        log_warn "  Package management will work, but file placement requires yq."
        log_warn "  Install with: sudo apt-get install -y yq"
        log_warn "  Or download: https://github.com/mikefarah/yq/releases"
        echo ""
        log_info "Continuing without yq — file placement will be skipped."
    fi

    # Check if already enrolled as this identity
    if is_enrolled; then
        local current
        current="$(current_identity)"
        if [[ "$current" == "$identity" ]]; then
            log_info "Already enrolled as '${identity}' — use 'nixnet apply' to update"
            return 0
        fi
        die "Already enrolled as '${current}'. Unenroll first or use a different identity."
    fi

    # Validate role directory exists
    if [[ ! -d "${NIXNET_WORLD}/roles/${role}" ]]; then
        log_warn "Role directory not found: ${NIXNET_WORLD}/roles/${role}"
        log_warn "Creating empty role directory"
        mkdir -p "${NIXNET_WORLD}/roles/${role}"/{files,hooks}
    fi

    # Check reclaim safety — warns if identity is claimed by another machine
    local identity_file="${NIXNET_WORLD}/hosts/${identity}/identity.yaml"
    if [[ -f "$identity_file" ]]; then
        if ! check_reclaim_safety "$identity" "$force"; then
            die "Enrollment aborted — identity not reclaimed."
        fi
    fi

    log_info "Enrolling as '${identity}' (role: ${role}, adopt: ${adopt})"

    # Step 1: Create or claim identity
    if [[ -f "$identity_file" ]]; then
        log_info "Claiming existing identity: ${identity}"
        update_claim "$identity"
    else
        create_identity "$identity" "$role"
    fi

    # Step 2: Set up local runtime
    ensure_runtime_dir
    write_local_claim "$identity" "$role"

    # Step 3: Adopt-specific inventory
    if $adopt; then
        export NIXNET_ADOPT=1
        enroll_adopt "$identity"
    fi

    # Step 4: Apply configuration
    log_info "Running initial apply..."
    cmd_apply

    # Step 5: Run enrollment hooks
    run_hooks "$identity" "$role" "post-enroll"

    log_ok "Enrollment complete: ${identity} (${role})"
}

# Adopt enrollment: snapshot existing state before applying
enroll_adopt() {
    local identity="$1"
    local adopted_dir="${NIXNET_LOCAL}/adopted"
    mkdir -p "$adopted_dir"

    log_info "Adopt mode: capturing existing state..."

    # Snapshot installed packages
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' \
        > "${adopted_dir}/packages.txt"
    local pkg_count
    pkg_count="$(wc -l < "${adopted_dir}/packages.txt")"
    log_ok "Captured ${pkg_count} installed packages"

    # Snapshot key config file checksums
    local checksum_file="${adopted_dir}/checksums.json"
    echo "{" > "$checksum_file"
    local first=true
    for f in ~/.bashrc ~/.bash_profile ~/.profile ~/.gitconfig ~/.ssh/config; do
        if [[ -f "$f" ]]; then
            local hash
            hash="$(sha256sum "$f" | awk '{print $1}')"
            if $first; then first=false; else echo "," >> "$checksum_file"; fi
            echo "  \"${f}\": \"${hash}\"" >> "$checksum_file"
        fi
    done
    echo "}" >> "$checksum_file"
    log_ok "Captured config checksums"

    log_info "Adopt snapshot saved to: ${adopted_dir}/"
    log_info "Apply will be additive-only — existing files will not be overwritten"
}
