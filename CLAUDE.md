# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What nixnet Is

A Git-backed host identity and continuity framework for Ubuntu-based Linux ecosystems. It treats machines as replaceable vessels and host identities as persistent objects. It begins at "fresh Linux plus enrollment" — nixnet does not create machines, it enrolls them.

## Architecture

**Two repos:**

- **Public engine** (this repo: `~/Projects/nixnet/`) — `bin/`, `lib/`, `schema/`, `bootstrap.sh`. Reusable framework. No private data.
- **Private world** (separate repo: `~/Projects/nixnet-world/`) — `global/`, `hosts/`. Real identities, layered config, ecosystem state.

The engine locates the world via: (1) `NIXNET_WORLD` env var, (2) saved path in `~/.nixnet/config`, (3) `./world/` fallback.

**Local Runtime** (`~/.nixnet/`) — per-machine identity receipt, config cache, and operational state. Created at enrollment. Contains `identity.json`, `config`, `state/`, `cache/`, `log/`, `snapshot/`.

### Core Concepts

- **Host identity** (`world/hosts/<hostname>/identity.yaml`): Named object that persists over time, outlives any machine instance. Has lifecycle state: `active | dormant | retired | destroyed`. Identity name always equals hostname.
- **Machine instance**: The actual running Linux box that claims a host identity. Identified by `/etc/machine-id`.
- **Layers**: Config resolves as `global → host` with simple union merging (packages) and last-layer-wins (files). No roles.
- **Enrollment**: Idempotent action that brings a machine into nixnet or refreshes an existing enrollment. Bootstrap script handles everything from a single curl command.

### Key Design Decisions

- **Machine loss ≠ identity destruction.** Deleting a VM moves the identity to `dormant`. Only `nixnet lifecycle set destroyed` is terminal.
- **Identity = hostname.** Always. No `--identity` flag, no separate naming.
- **No roles.** Layer model is `global → host`. Roles were removed as unnecessary complexity.
- **Convergent apply model.** `nixnet apply` installs missing packages and places missing/changed files. It never removes anything not in the declared layers.
- **Hybrid file placement.** Symlinks for user-space (`~/`), copies for system paths (`/etc/`, `/usr/`). Controlled by `method` field in `files.yaml` or auto-detected from target path.
- **Apply and sync are separate.** `apply` = local convergence (no network). `sync` = git coordination (explicit network).
- **Auto-commit for state files only.** `sync` auto-commits `identity.yaml` and `claim-history.txt`. Human-curated config is never auto-committed.
- **Enrollment is idempotent.** Running it again self-heals — updates claim, refreshes config, re-applies.
- **No secrets in v1.** The `secrets/` directory exists in the schema but apply/enroll code does not touch it.
- **Tailscale and SSH are existing infrastructure.** nixnet stands on top of them, does not manage them.

## Commands

```bash
# Validate bash syntax across all modules
bash -n lib/*.sh && bash -n bin/nixnet

# Bootstrap a new machine (one command)
curl -sL https://raw.githubusercontent.com/nixfred/nixnet/main/bootstrap.sh | bash -s -- git@github.com:nixfred/nixnet-world.git

# Run CLI (from repo root)
./bin/nixnet help
./bin/nixnet status
./bin/nixnet doctor

# Enroll this machine (identity = hostname)
./bin/nixnet enroll

# Apply layered config (convergent)
./bin/nixnet apply
./bin/nixnet apply --dry-run

# Sync world repo
./bin/nixnet sync
./bin/nixnet sync --dry-run

# Lifecycle transitions
./bin/nixnet lifecycle set dormant
./bin/nixnet lifecycle show
```

There is no build step. No test runner yet. Syntax validation is `bash -n`.

## Code Conventions

- Pure bash. No Python, no TypeScript, no external frameworks.
- `yq` for YAML parsing with grep/sed fallbacks when yq is absent. Ubuntu's `yq` is a Python jq-wrapper requiring `-yi` for in-place YAML writes (not `-i` like Mike Farah's Go binary).
- All lib files are sourced by `bin/nixnet` — they define functions, not standalone scripts.
- Functions prefixed by `cmd_` are CLI subcommand entry points.
- `NIXNET_ROOT`, `NIXNET_WORLD`, `NIXNET_LOCAL` are the three path anchors. All overridable via env vars.
- Colors/formatting are TTY-aware (disabled in pipes).
- Local config at `~/.nixnet/config` uses key=value format, not YAML.

## Layer Structure

Each layer (global, host) has the same shape:
```
packages.yaml    # apt package list (union merged across layers)
files/           # source files to place
files.yaml       # file placement manifest (src, dest, method, owner, mode)
hooks/           # executable scripts named by phase (post-enroll, post-apply)
```

## Proven (Proxmox Test 2026-03-08)

The following were validated on two disposable Ubuntu 24.04 VMs (fresh enroll on VM1, reclaim on VM2):

- Fresh enrollment creates identity with claim block and applies layered config
- Convergent apply is idempotent (second apply changes nothing)
- Doctor passes on both fresh and reclaimed machines
- Lifecycle transitions (`active → dormant → active`) work correctly
- Identity persists after machine destruction (VM1 destroyed, VM2 reclaimed)
- Reclaim detects foreign claim, archives old claim to `claim-history.txt`, warns before overwriting
- Host identity is independent of OS hostname (both VMs were `ub`, identity was `nixtest`)

## What nixnet Does NOT Manage (v1)

VM creation, package removal, drift detection, backups, secrets/vaults, remote orchestration, systemd services, monitoring, Tailscale/SSH configuration.
