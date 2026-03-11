#!/usr/bin/env bash
# nixnet — sync private world repo with remote
#
# 6-step sequence:
#   1. validate   — world is a git repo with a remote
#   2. capture    — recapture dotfiles and packages from live system
#   3. auto-commit — commit host state and captured files if changed
#   4. dirty check — two-tier policy on remaining uncommitted files
#   5. pull        — git pull --rebase from remote
#   6. push        — git push to remote
#
# Two-tier dirty file policy:
#   Tier 1 (warn-continue): dirty files in hosts/{self}/ outside state files
#   Tier 2 (warn-abort):    dirty files in global/ or hosts/{other}/

cmd_sync() {
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

    log_info "syncing world repo for ${name}..."
    echo ""

    # Step 1: Validate
    log_info "step 1/6: validating world repo..."
    sync_validate

    # Step 2: Capture current environment
    log_info "step 2/6: capturing environment..."
    if ! $dry_run; then
        capture_environment "$name"
    else
        log_info "would recapture dotfiles and packages"
    fi

    # Step 3: Auto-commit host state
    log_info "step 3/6: checking for host state changes..."
    sync_auto_commit "$name" "$dry_run"

    # Step 4: Dirty file check (two-tier)
    log_info "step 4/6: checking for dirty files..."
    if ! sync_check_dirty "$name"; then
        return 1
    fi

    # Step 5: Pull with rebase
    log_info "step 5/6: pulling remote changes..."
    sync_pull "$dry_run"

    # Step 6: Push
    log_info "step 6/6: pushing local changes..."
    sync_push "$dry_run"

    # Report
    echo ""
    if $dry_run; then
        log_ok "dry run complete — no changes made"
    else
        log_ok "sync complete for ${name}"
    fi
}

# Step 1: Validate that the world directory is a git repo with a remote
sync_validate() {
    [[ -d "$NIXNET_WORLD" ]] || die "World directory not found: ${NIXNET_WORLD}"

    if ! git -C "$NIXNET_WORLD" rev-parse --is-inside-work-tree &>/dev/null; then
        die "World directory is not a Git repository: ${NIXNET_WORLD}"
    fi

    local remote_count
    remote_count="$(git -C "$NIXNET_WORLD" remote | wc -l)"
    if [[ "$remote_count" -eq 0 ]]; then
        die "World repo has no remote configured. Add one with: git -C ${NIXNET_WORLD} remote add origin <url>"
    fi

    local remote
    remote="$(git -C "$NIXNET_WORLD" remote | head -1)"
    log_ok "world repo valid (remote: ${remote})"
}

# Step 2: Auto-commit allowed host state files if they have changed
sync_auto_commit() {
    local name="$1" dry_run="$2"

    # Host files that may be auto-committed (state + captured environment)
    local -a state_files=(
        "hosts/${name}/identity.yaml"
        "hosts/${name}/claim-history.txt"
        "hosts/${name}/packages.yaml"
        "hosts/${name}/files.yaml"
    )

    # Also include any captured dotfiles (dotglob needed for .bashrc etc.)
    if [[ -d "${NIXNET_WORLD}/hosts/${name}/files" ]]; then
        local _old_dotglob
        _old_dotglob="$(shopt -p dotglob 2>/dev/null || true)"
        shopt -s dotglob
        local f
        for f in "${NIXNET_WORLD}/hosts/${name}/files"/*; do
            [[ -f "$f" ]] || continue
            state_files+=("hosts/${name}/files/$(basename "$f")")
        done
        eval "$_old_dotglob"
    fi

    local -a changed=()
    for f in "${state_files[@]}"; do
        local full_path="${NIXNET_WORLD}/${f}"
        [[ -f "$full_path" ]] || continue

        # Check for any uncommitted changes (staged, unstaged, or untracked)
        local is_dirty=false
        if ! git -C "$NIXNET_WORLD" diff --quiet -- "$f" 2>/dev/null; then
            is_dirty=true
        elif ! git -C "$NIXNET_WORLD" diff --cached --quiet -- "$f" 2>/dev/null; then
            is_dirty=true
        elif git -C "$NIXNET_WORLD" ls-files --others --exclude-standard -- "$f" 2>/dev/null | grep -q .; then
            is_dirty=true
        fi

        if $is_dirty; then
            changed+=("$f")
        fi
    done

    if [[ ${#changed[@]} -eq 0 ]]; then
        log_ok "no host state changes to commit"
        return 0
    fi

    if $dry_run; then
        log_info "would auto-commit: ${changed[*]}"
        return 0
    fi

    git -C "$NIXNET_WORLD" add -- "${changed[@]}"

    local machine_id_short
    machine_id_short="$(get_machine_id | head -c 12)"

    git -C "$NIXNET_WORLD" commit -m "$(cat <<EOF
nixnet: auto-commit host state for ${name}

Updated: ${changed[*]}
Machine: $(hostname) (${machine_id_short}...)
Timestamp: $(now_iso)
EOF
)" 2>/dev/null || {
        log_info "nothing new to commit (state already current)"
        return 0
    }

    log_ok "auto-committed: ${changed[*]}"
}

# Step 3: Check for dirty files using two-tier policy
# Returns 0 if sync should proceed, 1 if sync should abort
sync_check_dirty() {
    local name="$1"

    # Get all remaining dirty files (modified, staged, untracked)
    local dirty_files
    dirty_files="$(git -C "$NIXNET_WORLD" status --porcelain 2>/dev/null)" || true

    if [[ -z "$dirty_files" ]]; then
        log_ok "working tree clean"
        return 0
    fi

    local -a tier1=()   # warn-continue: own host config outside state files
    local -a tier2=()   # warn-abort: shared layers or other hosts

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # git status --porcelain format: XY filename (or XY old -> new for renames)
        local file="${line:3}"
        # Handle renames: "R  old -> new" — use the new path
        if [[ "$file" == *" -> "* ]]; then
            file="${file##* -> }"
        fi

        # Classify the dirty file
        if [[ "$file" == hosts/${name}/* ]]; then
            # Own host subtree — Tier 1 (warn-continue)
            tier1+=("$file")
        elif [[ "$file" == global/* || "$file" == roles/* || "$file" == hosts/* ]]; then
            # Shared layers or other hosts — Tier 2 (warn-abort)
            tier2+=("$file")
        else
            # Root files (.gitignore, README, etc.) — Tier 1
            tier1+=("$file")
        fi
    done <<< "$dirty_files"

    # Report Tier 1 (warn-continue)
    if [[ ${#tier1[@]} -gt 0 ]]; then
        log_warn "uncommitted changes in your host config (continuing anyway):"
        for f in "${tier1[@]}"; do
            log_warn "  ${f}"
        done
    fi

    # Report Tier 2 (warn-abort)
    if [[ ${#tier2[@]} -gt 0 ]]; then
        log_error "uncommitted changes in shared layers — sync aborted"
        for f in "${tier2[@]}"; do
            log_error "  ${f}"
        done
        echo ""
        log_error "These files are in shared layers (global/, roles/, or another host's subtree)."
        log_error "Commit or stash them manually before running sync."
        return 1
    fi

    return 0
}

# Step 4: Pull from remote with rebase
sync_pull() {
    local dry_run="$1"

    if $dry_run; then
        log_info "would pull with rebase"
        return 0
    fi

    # Check if there's an upstream branch configured
    local upstream
    upstream="$(git -C "$NIXNET_WORLD" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || true

    if [[ -z "$upstream" ]]; then
        local remote branch
        remote="$(git -C "$NIXNET_WORLD" remote | head -1)"
        branch="$(git -C "$NIXNET_WORLD" rev-parse --abbrev-ref HEAD)"

        # Check if remote branch exists
        if git -C "$NIXNET_WORLD" ls-remote --heads "$remote" "$branch" 2>/dev/null | grep -q .; then
            git -C "$NIXNET_WORLD" branch --set-upstream-to="${remote}/${branch}" "$branch" 2>/dev/null || true
        else
            log_info "no remote branch yet — push will create it"
            return 0
        fi
    fi

    git -C "$NIXNET_WORLD" pull --rebase || die "pull failed — resolve conflicts manually in ${NIXNET_WORLD}"

    log_ok "pulled latest changes"
}

# Step 5: Push to remote
sync_push() {
    local dry_run="$1"

    if $dry_run; then
        log_info "would push to remote"
        return 0
    fi

    local remote branch
    remote="$(git -C "$NIXNET_WORLD" remote | head -1)"
    branch="$(git -C "$NIXNET_WORLD" rev-parse --abbrev-ref HEAD)"

    # Check if there's anything to push
    local has_upstream ahead
    has_upstream="$(git -C "$NIXNET_WORLD" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || has_upstream=""

    if [[ -n "$has_upstream" ]]; then
        ahead="$(git -C "$NIXNET_WORLD" rev-list --count '@{upstream}..HEAD' 2>/dev/null)" || ahead="0"
        if [[ "$ahead" -eq 0 ]]; then
            log_ok "nothing to push — already up to date"
            return 0
        fi
        log_info "pushing ${ahead} commit(s)..."
    fi

    git -C "$NIXNET_WORLD" push -u "$remote" "$branch" || die "push failed — check remote access"

    log_ok "pushed to ${remote}/${branch}"
}
