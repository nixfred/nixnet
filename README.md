# nixnet

A Git-backed host identity and continuity framework for Ubuntu-based Linux ecosystems.

nixnet treats machines as replaceable vessels and host identities as persistent objects. A host identity outlives any individual machine instance — when a VM is destroyed or a laptop is wiped, the identity moves to `dormant` and can be cleanly reclaimed by a new machine.

## Enroll a Machine

### Prerequisites (you handle these)

1. Ubuntu-based Linux with SSH access
2. SSH key on the machine that can clone your private world repo from GitHub
3. `sudo` access (bootstrap installs `git` and `yq` if missing)

### One Command

```bash
curl -sL https://raw.githubusercontent.com/nixfred/nixnet/main/bootstrap.sh | bash -s -- git@github.com:YOUR/world-repo.git
```

That's it. The bootstrap script:

1. Installs `git` and `yq` if missing
2. Clones the public engine to `~/Projects/nixnet/`
3. Clones your private world repo to `~/Projects/nixnet-world/`
4. Runs `nixnet enroll` (identity = hostname, always)

Re-running is safe — it pulls latest code and refreshes enrollment.

### What Enrollment Does

- **New machine, no existing identity:** Creates `hosts/<hostname>/identity.yaml` in the world repo, claims it, applies config.
- **New machine, dormant identity exists:** Auto-reclaims the identity, archives the old claim to `claim-history.txt`, sets lifecycle to `active`.
- **Already enrolled machine:** Refreshes the claim, re-applies config. Self-healing.

## Core Ideas

- **Host identity persists across machine destruction.** Deleting a VM does not destroy the identity. Only an explicit `nixnet lifecycle set destroyed` is terminal.
- **Identity equals hostname.** No configuration needed — the machine names itself.
- **Enrollment is idempotent.** Run it again to self-heal. It works whether the machine is new, already enrolled, or broken.
- **Dormant identities auto-reclaim.** A new machine with the same hostname as a dormant identity reclaims it automatically — no flags, no prompts.
- **Layered configuration.** Config resolves as `global → host` with union merging for packages and last-layer-wins for files.
- **Convergent apply.** `nixnet apply` installs missing packages and places missing/changed files. It never removes anything not in the declared layers.
- **Hybrid file placement.** Symlinks for user-space files (`~/`), copies for system paths (`/etc/`, `/usr/`).
- **Apply and sync are separate.** `apply` = local convergence (no network). `sync` = git coordination (explicit network).

## Architecture

nixnet uses two repositories:

- **Public engine** (this repo) — CLI, library functions, schema, bootstrap script. Reusable framework with no private data.
- **Private world** (separate repo) — Host identities, layered config, ecosystem state. Linked via `NIXNET_WORLD` env var or auto-discovered from `~/.nixnet/config`.

Each machine has a local runtime at `~/.nixnet/` containing its identity receipt, config cache, and operational state. Created at enrollment.

### World Discovery

After first enrollment, the world repo path is saved to `~/.nixnet/config`. On subsequent runs, nixnet finds the world automatically:

1. `NIXNET_WORLD` env var (explicit override)
2. Saved path in `~/.nixnet/config` (set during enrollment)
3. `./world/` fallback (development)

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
- Bash 5+
- SSH key with access to your private world repo on GitHub
- `sudo` access for package installation
- `git` and `yq` (bootstrap installs these automatically)
- Tailscale and SSH as existing infrastructure (nixnet does not manage them)

## File Structure

```
bin/nixnet          # CLI entry point
bootstrap.sh        # One-command enrollment for new machines
lib/
  common.sh         # Shared functions, logging, YAML helpers, config read/write
  identity.sh       # Identity creation, claim management, reclaim safety
  lifecycle.sh      # State transitions (active/dormant/retired/destroyed)
  config.sh         # Layer resolution (global -> host), convergent apply
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

## Lifecycle States

| State | Meaning |
|-------|---------|
| `active` | Identity is claimed by a running machine |
| `dormant` | Identity exists but no machine holds it — ready to be reclaimed |
| `retired` | Identity is preserved but no longer in use |
| `destroyed` | Terminal — identity record is kept but cannot be reclaimed |

Transitions: `active <-> dormant`, `active -> retired`, `dormant -> retired`, `retired -> destroyed`.

Dormant identities are automatically reclaimed when a new machine with the same hostname enrolls. No `--force` flag needed.

## Proven

Validated across two rounds of Proxmox VM testing (2026-03-08 and 2026-03-10) on disposable Ubuntu 24.04 VMs:

- Fresh enrollment creates identity with claim block and applies layered config
- Convergent apply is idempotent (second apply changes nothing)
- Doctor passes 8/8 on fresh, re-enrolled, and reclaimed machines
- Re-enrollment is idempotent — refreshes claim, re-applies config, archives old claim
- Lifecycle transitions (`active -> dormant -> active`) work correctly
- Dormant identities auto-reclaim via bootstrap without interactive prompts
- Foreign claims are archived to `claim-history.txt` with timestamps
- Identity persists after machine destruction (VM destroyed, new VM reclaimed identity)

## What nixnet Does NOT Manage (v1)

VM creation, package removal, drift detection, backups, secrets/vaults, remote orchestration, systemd services, monitoring, Tailscale/SSH configuration.

## License

MIT
