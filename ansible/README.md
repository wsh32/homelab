# Ansible

Push-only configuration management for all homelab nodes.

## Usage

```bash
# Configure everything
ansible-playbook site.yml

# Limit to a single host
ansible-playbook site.yml --limit machamp-dev

# Run a specific playbook
ansible-playbook dev.yml
```

Tailscale bootstrap is excluded from `site.yml` — run it separately with a key:

```bash
TAILSCALE_AUTH_KEY=<key> ansible-playbook tailscale.yml
```

## Inventory

The inventory is generated dynamically from two files:

- **`../network.yml`** — single source of truth for all IPs and node definitions
- **`group_config.yml`** — maps Proxmox node names to Ansible groups and vars

Run `python3 inventory/homelab.py` to inspect the generated inventory.

### Groups

| Group | Members |
|-------|---------|
| `physical` | All non-VM nodes (proxmox, nas, other) |
| `proxmox` | Proxmox hypervisors |
| `vms` | All Ansible-managed VMs |
| `diglett_vms` | VMs on diglett |
| `machamp_vms` | VMs on machamp |
| `dev` | VMs tagged `vm_roles: [dev]` in network.yml |

Role groups (`dev`, etc.) are created dynamically — any `vm_roles` value in
`network.yml` automatically becomes an inventory group.

## Playbooks

| Playbook | Targets | Purpose |
|----------|---------|---------|
| `site.yml` | _(all below)_ | Run everything in order |
| `network.yml` | `proxmox` | Static IP / bridge config on Proxmox nodes |
| `physical.yml` | `physical` | Base config for physical devices |
| `base.yml` | `vms` | Base config for all VMs |
| `deploy-vm.yml` | `alakazam-deploy` | Deploy VM tooling (Terraform, Infisical, Ansible) |
| `dev.yml` | `dev` | Developer tooling for dev VMs |
| `tailscale.yml` | `physical` | Bootstrap Tailscale (requires `TAILSCALE_AUTH_KEY`) |
| `dns.yml` | `diglett-dns` | Deploy AdGuard Home + Headscale (HTTPS/443, Let's Encrypt DNS-01) + cloudflare-ddns |

## Roles

| Role | Applied by | Purpose |
|------|-----------|---------|
| `base` | `base.yml`, `physical.yml`, `deploy-vm.yml` | Packages, SSH hardening, UFW, fail2ban |
| `network` | `network.yml` | `/etc/network/interfaces` for Proxmox bridge |
| `deploy` | `deploy-vm.yml` | Terraform, Infisical CLI, Ansible via pipx |
| `docker` | _(not yet wired up)_ | Docker CE + compose plugin |
| `dev` | `dev.yml` | Dev tooling — see below |
| `headscale` | `dns.yml` | Headscale + cloudflare-ddns Docker Compose stack on the DNS VM |

### dev role

Installed on VMs tagged with `vm_roles: [dev]` in `network.yml`.

- Build tools: `build-essential`, `gcc`, `g++`, `make`, `cmake`, `pkg-config`
- Python: `python3-dev`, `python3-pip`, `python3-venv`
- Node.js LTS (NodeSource), Rust (rustup)
- Dev CLI: `jq`, `ripgrep`, `fd-find`, `bat`, `fzf`, `direnv`, `strace`, `gdb`
- GitHub CLI (`gh`) — auth via Infisical GITHUB_TOKEN is a future TODO
- Claude Code (`npm install -g @anthropic-ai/claude-code`)
- zsh + oh-my-zsh (custom `.zshrc` pulled from dotfiles repo separately)
- base16-shell with `base16-google-dark` theme

## Adding a new VM role

1. Add `vm_roles: [<name>]` to the VM entry in `../network.yml`
2. Create `roles/<name>/tasks/main.yml` and `roles/<name>/handlers/main.yml`
3. Create `<name>.yml` playbook targeting the `<name>` group
4. Add it to `site.yml`
