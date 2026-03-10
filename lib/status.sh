#!/usr/bin/env bash
# nixnet — status display

cmd_status() {
    if ! is_enrolled; then
        log_info "Not enrolled"
        echo "  Run: nixnet enroll --identity NAME --role ROLE"
        return 0
    fi

    local name role
    name="$(current_identity)"
    role="$(current_role)"

    local identity_file="${NIXNET_WORLD}/hosts/${name}/identity.yaml"
    local lifecycle="unknown"
    if [[ -f "$identity_file" ]]; then
        lifecycle="$(yaml_read "$identity_file" "lifecycle")"
    fi

    local last_apply="never"
    if [[ -f "${NIXNET_LOCAL}/state/last-apply.json" ]]; then
        if command -v jq &>/dev/null; then
            last_apply="$(jq -r '.applied_at' "${NIXNET_LOCAL}/state/last-apply.json")"
        else
            last_apply="$(grep 'applied_at' "${NIXNET_LOCAL}/state/last-apply.json" | sed 's/.*: *"\(.*\)".*/\1/')"
        fi
    fi

    echo -e "${_BOLD}nixnet status${_RESET}"
    echo "---"
    echo "  Identity:   ${name}"
    echo "  Role:       ${role}"
    echo "  Lifecycle:  ${lifecycle}"
    echo "  Machine ID: $(get_machine_id)"
    echo "  Hostname:   $(hostname)"
    echo "  Last apply: ${last_apply}"
    echo "  Runtime:    ${NIXNET_LOCAL}"
    echo "  World:      ${NIXNET_WORLD}"
}
