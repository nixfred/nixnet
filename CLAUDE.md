# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What nixnet Is

A Git-backed host identity and continuity framework for Ubuntu-based Linux ecosystems. It treats machines as replaceable vessels and host identities as persistent objects. It begins at "fresh Linux plus enrollment" — nixnet does not create machines, it enrolls them.

## Architecture

**Two repos:**

- **Public engine** (this repo: `~/Projects/nixnet/`) — `bin/`, `lib/`, `schema/`, `docs/`. Reusable framework. No private data.
- **Private world** (separate repo: `~/Projects/nixnet-world/`) — `global/`, `roles/`, `hosts/`. Real identities, layered config, ecosystem state.

The engine locates the world via `NIXNET_WORLD` env var. Default is `./world/` (for colocated dev), override with the private repo path.

**Local Runtime** (`~/.local/nixnet/`) — per-machine claim receipt and operational state. Created at enrollment. Contains `identity.json`, `state/`, `cache/`, `log/`.

### Core Concepts

- **Host identity** (`world/hosts/<name>/identity.yaml`): Named object that persists over time, outlives any machine instance. Has lifecycle state: `active | dormant | retired | destroyed`.
- **Machine instance**: The actual running Linux box that claims a host identity. Identified by `/etc/machine-id`.
- **Layers**: Config resolves as `global → role → host` with simple union merging (packages) and last-layer-wins (files).
- **Enrollment**: Action (not a state) that brings a machine into nixnet. Two paths: fresh (clean install) and adopt (existing working machine, additive-only).

### Key Design Decisions

- **Machine loss ≠ identity destruction.** Deleting a VM moves the identity to `dormant`. Only `nixnet lifecycle set destroyed` is terminal.
- **Convergent apply model.** `nixnet apply` installs missing packages and places missing/changed files. It never removes anything not in the declared layers.
- **Hybrid file placement.** Symlinks for user-space (`~/`), copies for system paths (`/etc/`, `/usr/`). Controlled by `method` field in `files.yaml` or auto-detected from target path.
- **No secrets in v1.** The `secrets/` directory exists in the schema but apply/enroll code does not touch it.
- **Tailscale and SSH are existing infrastructure.** nixnet stands on top of them, does not manage them.

## Commands

```bash
# Validate bash syntax across all modules
bash -n lib/*.sh && bash -n bin/nixnet

# Run CLI (from repo root)
./bin/nixnet help
./bin/nixnet status
./bin/nixnet doctor

# Enroll this machine (fresh)
./bin/nixnet enroll --identity NAME --role ROLE

# Enroll existing machine (additive-only, snapshots current state)
./bin/nixnet enroll --identity NAME --role ROLE --adopt

# Apply layered config (convergent)
./bin/nixnet apply
./bin/nixnet apply --dry-run

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

## Layer Structure

Each layer (global, role, host) has the same shape:
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
- Doctor passes 9/9 on both fresh and reclaimed machines
- Lifecycle transitions (`active → dormant → active`) work correctly
- Identity persists after machine destruction (VM1 destroyed, VM2 reclaimed)
- Reclaim detects foreign claim, archives old claim to `claim-history.txt`, warns before overwriting
- Host identity is independent of OS hostname (both VMs were `ub`, identity was `nixtest`)

## What nixnet Does NOT Manage (v1)

VM creation, package removal, drift detection, backups, secrets/vaults, remote orchestration, systemd services, monitoring, Tailscale/SSH configuration.
