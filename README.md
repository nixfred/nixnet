# nixnet

A Git-backed host identity and continuity framework for Ubuntu-based Linux ecosystems.

nixnet treats machines as replaceable vessels and host identities as persistent objects. A host identity outlives any individual machine instance — when a VM is destroyed or a laptop is wiped, the identity moves to `dormant` and can be cleanly reclaimed by a new machine.

## Enroll a Machine

```bash
curl -sL https://raw.githubusercontent.com/nixfred/nixnet/main/bootstrap.sh | bash -s -- git@github.com:YOUR/world-repo.git
```

One command. Installs prerequisites, clones repos, enrolls the machine. Identity equals hostname. Re-running is safe — it updates code and refreshes enrollment.

## Core Ideas

- **Host identity persists across machine destruction.** Deleting a VM does not destroy the identity. Only an explicit `nixnet lifecycle set destroyed` is terminal.
- **Identity equals hostname.** No configuration needed — the machine names itself.
- **Enrollment is idempotent.** Run it again to self-heal. It works whether the machine is new, already enrolled, or broken.
- **Layered configuration.** Config resolves as `global → host` with union merging for packages and last-layer-wins for files.
- **Convergent apply.** `nixnet apply` installs missing packages and places missing/changed files. It never removes anything not in the declared layers.
- **Hybrid file placement.** Symlinks for user-space files (`~/`), copies for system paths (`/etc/`, `/usr/`).

## Architecture

nixnet uses two repositories:

- **Public engine** (this repo) — CLI, library functions, schema, bootstrap script. Reusable framework with no private data.
- **Private world** (separate repo) — Host identities, layered config, ecosystem state. Linked via `NIXNET_WORLD` env var or auto-discovered from `~/.nixnet/config`.

Each machine has a local runtime at `~/.nixnet/` containing its identity receipt, config cache, and operational state.

## Commands

```bash
# Enroll this machine (identity = hostname, always)
./bin/nixnet enroll

# Apply layered config (convergent)
./bin/nixnet apply
./bin/nixnet apply --dry-run

# Sync world repo (auto-commit state, pull, push)
./bin/nixnet sync
./bin/nixnet sync --dry-run

# Check health
./bin/nixnet doctor

# View status
./bin/nixnet status

# Lifecycle transitions
./bin/nixnet lifecycle set dormant
./bin/nixnet lifecycle show
```

## Requirements

- Ubuntu-based Linux (tested on Ubuntu 24.04 LTS)
- `yq` for YAML parsing (`sudo apt install yq`)
- Bash 5+
- Tailscale and SSH as existing infrastructure (nixnet does not manage them)

## File Structure

```
bin/nixnet          # CLI entry point
bootstrap.sh        # One-command enrollment for new machines
lib/
  common.sh         # Shared functions, logging, YAML helpers, config read/write
  identity.sh       # Identity creation, claim management, reclaim safety
  lifecycle.sh      # State transitions (active/dormant/retired/destroyed)
  config.sh         # Layer resolution (global → host), convergent apply
  enroll.sh         # Enrollment logic (idempotent, self-healing)
  sync.sh           # World repo sync (auto-commit, pull, push, dirty-file policy)
  doctor.sh         # 8 health checks
  status.sh         # Status display
schema/
  host-identity.yaml  # Reference schema
```

## World Repo Structure

The private world repo follows a layered pattern:

```
global/
  packages.yaml     # Packages for all hosts
  files.yaml        # File placements for all hosts
  files/            # Source files
  hooks/            # Global hooks
hosts/<hostname>/
  identity.yaml     # Host identity with claim block
  claim-history.txt # Archived previous claims
  packages.yaml     # Host-specific packages
  files.yaml        # Host-specific file placements
  files/
  hooks/            # Host-specific hooks (post-enroll, post-apply)
```

## Sync Behavior

`nixnet sync` coordinates the world repo with the remote:

1. **Validate** — confirms world is a git repo with a remote
2. **Auto-commit** — commits host state files (`identity.yaml`, `claim-history.txt`) if changed
3. **Dirty check** — two-tier policy:
   - Your own host config: warn and continue
   - Shared layers or other hosts: warn and abort
4. **Pull** — `git pull --rebase`
5. **Push** — `git push`

## Status

The central architectural claim has been proven: **a host identity can outlive a machine instance and be cleanly reclaimed by a new one.** Validated on 2026-03-08 with two disposable Proxmox VMs — fresh enrollment, lifecycle transition, identity persistence after destruction, and clean reclaim with claim history preservation.

## License

MIT
