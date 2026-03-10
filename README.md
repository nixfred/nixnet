# nixnet

A Git-backed host identity and continuity framework for Ubuntu-based Linux ecosystems.

nixnet treats machines as replaceable vessels and host identities as persistent objects. A host identity outlives any individual machine instance — when a VM is destroyed or a laptop is wiped, the identity moves to `dormant` and can be cleanly reclaimed by a new machine.

## Core Ideas

- **Host identity persists across machine destruction.** Deleting a VM does not destroy the identity. Only an explicit `nixnet lifecycle set destroyed` is terminal.
- **Enrollment is an action, not a state.** Machines are enrolled into existing identities. Two paths: fresh (clean install) and adopt (existing working machine, additive-only).
- **Layered configuration.** Config resolves as `global → role → host` with union merging for packages and last-layer-wins for files.
- **Convergent apply.** `nixnet apply` installs missing packages and places missing/changed files. It never removes anything not in the declared layers.
- **Hybrid file placement.** Symlinks for user-space files (`~/`), copies for system paths (`/etc/`, `/usr/`).

## Architecture

nixnet uses two repositories:

- **Public engine** (this repo) — CLI, library functions, schema. Reusable framework with no private data.
- **Private world** (separate repo) — Host identities, layered config, ecosystem state. Linked via `NIXNET_WORLD` env var.

Each machine has a local runtime at `~/.local/nixnet/` containing its claim receipt and operational state.

## Quick Start

```bash
# Set world repo location
export NIXNET_WORLD=/path/to/your/nixnet-world

# Enroll this machine
./bin/nixnet enroll --identity myhost --role myrole

# Apply layered config
./bin/nixnet apply

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
lib/
  common.sh         # Shared functions, logging, YAML helpers
  identity.sh       # Identity creation, claim management, reclaim safety
  lifecycle.sh      # State transitions (active/dormant/retired/destroyed)
  config.sh         # Layer resolution, convergent apply
  enroll.sh         # Enrollment logic (fresh and adopt paths)
  doctor.sh         # 9 health checks
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
roles/<role>/
  packages.yaml     # Role-specific packages
  files.yaml        # Role-specific file placements
  files/
hosts/<name>/
  identity.yaml     # Host identity with claim block
  claim-history.txt # Archived previous claims
  packages.yaml     # Host-specific packages
  files.yaml        # Host-specific file placements
  files/
  hooks/            # Lifecycle hooks (post-enroll, post-apply)
  secrets/          # Reserved for v2
```

## Status

The central architectural claim has been proven: **a host identity can outlive a machine instance and be cleanly reclaimed by a new one.** Validated on 2026-03-08 with two disposable Proxmox VMs — fresh enrollment, lifecycle transition, identity persistence after destruction, and clean reclaim with claim history preservation.

## License

MIT
