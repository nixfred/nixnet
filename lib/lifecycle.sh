#!/usr/bin/env bash
# nixnet — lifecycle state management

VALID_STATES=("active" "dormant" "retired" "destroyed")

# Manage lifecycle state
cmd_lifecycle() {
    local action="${1:-}"
    shift || true

    case "$action" in
        set)  lifecycle_set "$@" ;;
        show) lifecycle_show ;;
        *)
            echo "Usage: nixnet lifecycle <set|show>"
            echo "  set <active|dormant|retired|destroyed>"
            echo "  show"
            exit 1
            ;;
    esac
}

lifecycle_set() {
    local new_state="${1:-}"
    [[ -n "$new_state" ]] || die "Usage: nixnet lifecycle set <state>"

    is_enrolled || die "Not enrolled"

    # Validate state
    local valid=false
    for s in "${VALID_STATES[@]}"; do
        [[ "$s" == "$new_state" ]] && valid=true
    done
    $valid || die "Invalid state: ${new_state}. Valid: ${VALID_STATES[*]}"

    local name
    name="$(current_identity)"
    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    [[ -f "$identity_file" ]] || die "Identity file not found: ${identity_file}"

    local current_state
    current_state="$(yaml_read "$identity_file" "lifecycle")"

    # Transition guards
    case "${current_state}:${new_state}" in
        active:dormant|active:retired)  ;;  # valid
        dormant:active|dormant:retired) ;;  # valid (reclaim)
        retired:destroyed)              ;;  # valid (terminal)
        *:*)
            if [[ "$current_state" == "$new_state" ]]; then
                log_info "Already in state: ${new_state}"
                return 0
            fi
            die "Invalid transition: ${current_state} → ${new_state}"
            ;;
    esac

    # Apply the transition
    if command -v yq &>/dev/null; then
        yq -yi ".lifecycle = \"${new_state}\"" "$identity_file"
    else
        sed -i "s/^lifecycle:.*/lifecycle: ${new_state}/" "$identity_file"
    fi

    # If going dormant, clear the claim but keep identity
    if [[ "$new_state" == "dormant" ]]; then
        log_info "Identity '${name}' is now dormant — machine claim preserved in history"
    fi

    # Update local state
    echo "{\"lifecycle\": \"${new_state}\", \"changed_at\": \"$(now_iso)\"}" \
        > "${NIXNET_LOCAL}/state/lifecycle.json"

    log_ok "Lifecycle: ${name} ${current_state} → ${new_state}"
}

lifecycle_show() {
    is_enrolled || die "Not enrolled. Run: nixnet enroll"

    local name
    name="$(current_identity)"
    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    local state
    state="$(yaml_read "$identity_file" "lifecycle")"

    echo "${state}"
}
