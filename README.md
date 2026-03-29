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

# Fill in terraform.tfvars (Proxmox tokens, Tailscale key, SSH key, ACME email)
# Provision all VMs
cd terraform/nuc && terraform apply
cd terraform/anton && terraform apply

# Bootstrap Infisical — outputs workspace_id, client_id, client_secret
./scripts/infisical-bootstrap.sh

# Add Infisical credentials to terraform.tfvars, re-apply
cd terraform/nuc && terraform apply
cd terraform/anton && terraform apply

# Create Vaultwarden account at https://vault.home (one manual step, ever)

# Seed all secrets into Infisical UI:
#   - Service API keys and inter-service tokens
#   - Developer API keys (Claude, Codex, GitHub, etc.)

# Reboot VMs — services fetch secrets from Infisical and start up
```

## Secrets

Two stores with distinct roles:

| Store | What | How populated |
|-------|------|---------------|
| **`terraform.tfvars`** | Infrastructure credentials (Proxmox, Tailscale, SSH key, ACME email, Infisical credentials) | Manually |
| **Infisical** | All machine-consumed secrets: service API keys, inter-service tokens, developer API keys | Manually via Infisical UI after bootstrap |
| **Vaultwarden** | Human-consumed secrets: web UI admin passwords, personal credentials | Manually when setting up each service |

VMs fetch secrets from Infisical at boot via `infisical export` to generate ephemeral `.env` files.
Containers read `.env` at startup. Vaultwarden is for humans — never automated via Terraform.

Never commit `.env`, `terraform.tfvars`, or `*.tfstate`.

## Hardware

See [`docs/hardware_inventory.md`](docs/hardware_inventory.md).
