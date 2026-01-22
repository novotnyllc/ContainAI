# fn-10-vep.41 Generate dedicated SSH key and setup ~/.config/containai/

## Description
Generate a dedicated ed25519 SSH key for ContainAI during `cai setup`.

**Size:** S
**Files:** lib/setup.sh, lib/ssh.sh (new)

## Approach

1. Create `lib/ssh.sh` with SSH-related functions
2. In `_cai_setup_ssh_key()`:
   - Create `~/.config/containai/` directory (700 permissions)
   - Generate ed25519 key: `ssh-keygen -t ed25519 -f ~/.config/containai/id_containai -N "" -C "containai"`
   - Set permissions: 600 on private key, 644 on public key

## Key context

- ed25519 is preferred over RSA for modern systems
- No passphrase (-N "") for non-interactive use
- Key comment identifies it as ContainAI's key
## Acceptance
- [ ] `~/.config/containai/` directory created with 700 permissions
- [ ] `~/.config/containai/id_containai` (private key) created with 600 permissions
- [ ] `~/.config/containai/id_containai.pub` (public key) created
- [ ] Key is ed25519 type
- [ ] Idempotent: re-running setup does not overwrite existing key
- [ ] `config.toml` created in same directory (can be empty initially)
## Done summary
Created `src/lib/ssh.sh` with `_cai_setup_ssh_key()` function that generates dedicated ed25519 SSH key at `~/.config/containai/id_containai` during `cai setup`. Key creates config directory with 700 permissions, private key with 600, public key with 644, and empty config.toml. Idempotent - does not overwrite existing keys. Integrated into main `_cai_setup()` flow.
## Evidence
- Commits: 28d8ad1
- Tests: Manual: verified ssh.sh sourcing, key generation, permissions (700/600/644), idempotence
- PRs: