#!/usr/bin/env bash
# nixnet — layered configuration resolution and convergent apply
#
# Layer model: global → host (roles removed in v0.3.0)

cmd_apply() {
    local dry_run=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    is_enrolled || die "Not enrolled. Run: nixnet enroll"

    local name
    name="$(current_identity)"

    log_info "Applying configuration for ${name}"

    # Phase 1: Resolve layers (global → host)
    local resolved_dir="${NIXNET_LOCAL}/cache/resolved"
    mkdir -p "$resolved_dir"
    resolve_packages "$name" "$resolved_dir"
    resolve_files "$name" "$resolved_dir"

    # Phase 2: Apply (convergent)
    if $dry_run; then
        log_info "=== DRY RUN ==="
    fi
    apply_packages "$resolved_dir" "$dry_run"
    apply_files "$resolved_dir" "$dry_run"

    # Phase 3: Run hooks
    if ! $dry_run; then
        run_hooks "$name" "post-apply"
    fi

    # Record apply
    if ! $dry_run; then
        cat > "${NIXNET_LOCAL}/state/last-apply.json" <<EOF
{
  "identity": "${name}",
  "applied_at": "$(now_iso)",
  "result": "success"
}
EOF
        log_ok "Apply complete for ${name}"
    fi
}

# Resolve packages from all layers into a single union list
resolve_packages() {
    local name="$1" resolved_dir="$2"
    local merged="${resolved_dir}/packages.list"

    : > "$merged"  # truncate

    # Global packages
    local global_pkg="${NIXNET_WORLD}/global/packages.yaml"
    [[ -f "$global_pkg" ]] && yaml_read_list "$global_pkg" "packages" >> "$merged"

    # Host packages
    local host_pkg="${NIXNET_WORLD}/hosts/${name}/packages.yaml"
    [[ -f "$host_pkg" ]] && yaml_read_list "$host_pkg" "packages" >> "$merged"

    # Deduplicate (union)
    if [[ -s "$merged" ]]; then
        sort -u "$merged" -o "$merged"
    fi
}

# Resolve files from all layers (host wins over global for same dest)
resolve_files() {
    local name="$1" resolved_dir="$2"
    local merged="${resolved_dir}/files.list"

    : > "$merged"

    # Collect files.yaml from each layer (later wins on conflict)
    local layer_files
    for layer_files in \
        "${NIXNET_WORLD}/global/files.yaml" \
        "${NIXNET_WORLD}/hosts/${name}/files.yaml"; do
        if [[ -f "$layer_files" ]]; then
            echo "$layer_files" >> "$merged"
        fi
    done
}

# Install missing packages (convergent — never removes)
apply_packages() {
    local resolved_dir="$1" dry_run="$2"
    local pkg_list="${resolved_dir}/packages.list"

    [[ -s "$pkg_list" ]] || return 0

    local missing=()
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            missing+=("$pkg")
        fi
    done < "$pkg_list"

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_ok "All packages already installed"
        return 0
    fi

    if $dry_run; then
        log_info "Would install: ${missing[*]}"
        return 0
    fi

    log_info "Installing ${#missing[@]} packages: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}" || die "Package installation failed"
    log_ok "Packages installed"
}

# Apply file placements (convergent — symlinks for user-space, copies for system)
apply_files() {
    local resolved_dir="$1" dry_run="$2"
    local file_index="${resolved_dir}/files.list"

    [[ -s "$file_index" ]] || return 0

    # Process each layer's files.yaml
    while IFS= read -r layer_file; do
        local layer_dir
        layer_dir="$(dirname "$layer_file")"

        # Read entries from files.yaml
        # Each entry: src, dest, method (symlink|copy), owner, mode
        if command -v yq &>/dev/null; then
            local count
            count="$(yq '.files | length' "$layer_file" 2>/dev/null)" || continue
            for ((i=0; i<count; i++)); do
                local src dest method
                src="$(yq -r ".files[$i].src" "$layer_file")"
                dest="$(yq -r ".files[$i].dest" "$layer_file")"
                method="$(yq -r ".files[$i].method // \"auto\"" "$layer_file")"

                local full_src="${layer_dir}/files/${src}"
                [[ -f "$full_src" ]] || { log_warn "Source not found: ${full_src}"; continue; }

                # Expand ~ in dest
                dest="${dest/#\~/$HOME}"

                # Auto-detect method if not specified
                if [[ "$method" == "auto" ]]; then
                    if [[ "$dest" == /etc/* || "$dest" == /usr/* ]]; then
                        method="copy"
                    else
                        method="symlink"
                    fi
                fi

                if $dry_run; then
                    log_info "Would ${method}: ${full_src} → ${dest}"
                    continue
                fi

                # Ensure parent directory exists
                mkdir -p "$(dirname "$dest")"

                case "$method" in
                    symlink)
                        if [[ -L "$dest" && "$(readlink "$dest")" == "$full_src" ]]; then
                            continue  # already correct
                        fi
                        ln -sf "$full_src" "$dest"
                        log_ok "Symlinked: ${dest} → ${full_src}"
                        ;;
                    copy)
                        if [[ -f "$dest" ]] && diff -q "$full_src" "$dest" &>/dev/null; then
                            continue  # already identical
                        fi
                        local owner mode
                        owner="$(yq -r ".files[$i].owner // empty" "$layer_file")"
                        mode="$(yq -r ".files[$i].mode // empty" "$layer_file")"

                        if [[ "$dest" == /etc/* || "$dest" == /usr/* ]]; then
                            sudo cp "$full_src" "$dest"
                            [[ -n "$owner" ]] && sudo chown "$owner" "$dest"
                            [[ -n "$mode" ]] && sudo chmod "$mode" "$dest"
                        else
                            cp "$full_src" "$dest"
                            [[ -n "$mode" ]] && chmod "$mode" "$dest"
                        fi
                        log_ok "Copied: ${full_src} → ${dest}"
                        ;;
                esac
            done
        else
            log_warn "yq not available — skipping file placement from ${layer_file}"
        fi
    done < "$file_index"
}

# Run hooks from all layers for a given phase
run_hooks() {
    local name="$1" phase="$2"

    for hook_dir in \
        "${NIXNET_WORLD}/global/hooks" \
        "${NIXNET_WORLD}/hosts/${name}/hooks"; do
        local hook="${hook_dir}/${phase}"
        if [[ -x "$hook" ]]; then
            log_info "Running hook: ${hook}"
            "$hook" || log_warn "Hook returned non-zero: ${hook}"
        fi
    done
}
