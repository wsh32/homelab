# homelab

Infrastructure-as-code for a Proxmox-based homelab. All compute is defined in Terraform and reproducible from this repo.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          Tailscale mesh                           │
│                                                                  │
│  ┌───────────────┐   ┌────────────────┐   ┌──────────────────┐  │
│  │     Anton     │   │      NUC       │   │    Storinator    │  │
│  │   (compute)   │   │    (infra)     │   │      (NAS)       │  │
│  │               │   │                │   │                  │  │
│  │ • Ollama      │   │ • AdGuard DNS  │   │ • TrueNAS        │  │
│  │ • OpenClaw    │   │ • Home Asst.   │   │ • NFS exports    │  │
│  │ • Traefik *   │   │ • Infisical    │   │                  │  │
│  │ • Jellyfin *  │   │ • Vaultwarden  │   └──────────────────┘  │
│  │ • Servarr *   │   │                │   ┌──────────────────┐  │
│  │ • PhotoPrism *│   └────────────────┘   │    Gringotts     │  │
│  │ • n8n *       │                        │ (offsite backup) │  │
│  │ • Monitoring *│                        └──────────────────┘  │
│  │ • Obsidian *  │                                              │
│  │ • Quartz *    │                                              │
│  └───────────────┘                                              │
│                                                                  │
│  * migrates to services node when built                          │
└──────────────────────────────────────────────────────────────────┘
```

See [`docs/plan.md`](docs/plan.md) for full architecture, VM layout, and all decisions.

## Repo structure

```
terraform/
  modules/proxmox-vm/   # shared VM module (bpg/proxmox provider)
  nuc/                  # NUC root module
  anton/                # Anton root module
services/
  dns/                  # AdGuard config (pre-seeded, no setup wizard)
  nuc-infra/            # Docker Compose — NUC infra VM
  anton/                # Docker Compose — Anton services VM
scripts/
  infisical-bootstrap.sh  # bootstraps Infisical after first apply
  jellyfin-init.sh        # headless Jellyfin setup via API
  servarr-init.sh         # links Prowlarr to Radarr/Sonarr
  calibre-init.sh         # sets Calibre-Web admin password
  n8n-init.sh             # creates n8n owner account
cloud-init/
  base.yaml             # base cloud-init for all VMs
  docker-host.yaml      # extended cloud-init for Docker Compose VMs
docs/
  plan.md               # architecture plan and all decisions
  hardware_inventory.md # hardware reference
  TODOS.md              # deferred work items
```

## Bootstrap

Full details in [`docs/plan.md`](docs/plan.md#bootstrap-phase). Summary:

**Manual (one-time):**
1. Join Anton and NUC into a Proxmox cluster via UI
2. Create Proxmox API token for Terraform on each node
3. Create NFS datasets on Storinator (`terraform-state`, `docker`) via TrueNAS UI
4. Generate Tailscale API key in the Tailscale dashboard

**Automated:**
```bash
# Install Tailscale on physical nodes
ansible-playbook ansible/tailscale.yml

# Pass 1 — provision all VMs (Infisical not yet configured)
cd terraform/nuc && terraform apply
cd terraform/anton && terraform apply

# Bootstrap Infisical (creates workspace + machine identity)
# Outputs workspace_id, client_id, client_secret — add to terraform.tfvars
./scripts/infisical-bootstrap.sh

# Pass 2 — seed all secrets into Infisical
cd terraform/nuc && terraform apply
cd terraform/anton && terraform apply
```

## Secrets

Secrets are managed by self-hosted [Infisical](https://infisical.com) (NUC Infisical VM).

- **Infrastructure secrets** (service passwords, API keys) — seeded by Terraform during pass 2 apply; injected into containers at startup
- **Developer API keys** (Claude, Codex, GitHub, etc.) — stored in Infisical, accessed on the operator laptop via `infisical run -- <command>`
- **`terraform.tfvars`** — Proxmox token, Tailscale key, and Infisical credentials; gitignored, backed up in Vaultwarden
- Never commit `.env`, `terraform.tfvars`, or `*.tfstate`

## Hardware

See [`docs/hardware_inventory.md`](docs/hardware_inventory.md).
