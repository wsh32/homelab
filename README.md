# homelab

Infrastructure-as-code for a Proxmox-based homelab. All compute is defined in Terraform, reproducible from this repo, and deployed automatically on push to `main`.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Headscale tailnet                                │
│                                                                         │
│  ┌──────────┐   ┌───────────────┐   ┌────────────────┐   ┌───────────┐ │
│  │   VPS    │   │     Anton     │   │      NUC       │   │Storinator │ │
│  │   (DO)   │   │   (compute)   │   │    (infra)     │   │  (NAS)    │ │
│  │          │   │               │   │                │   │           │ │
│  │Headscale │   │ • Ollama      │   │ • AdGuard DNS  │   │ • TrueNAS │ │
│  │Terraform │   │ • OpenClaw    │   │ • Home Asst.   │   │ • NFS     │ │
│  │Webhook   │   │ • Traefik *   │   │ • Infisical    │   │ • MinIO   │ │
│  └──────────┘   │ • Jellyfin *  │   │ • Vaultwarden  │   └───────────┘ │
│                 │ • Servarr *   │   │                │   ┌───────────┐ │
│                 │ • PhotoPrism *│   └────────────────┘   │Gringotts  │ │
│                 │ • n8n *       │                        │ (offsite) │ │
│                 │ • Monitoring *│                        └───────────┘ │
│                 │ • Obsidian *  │                                       │
│                 │ • Quartz *    │                                       │
│                 └───────────────┘                                       │
│                                                                         │
│  * migrates to services node when built                                 │
└─────────────────────────────────────────────────────────────────────────┘
```

**VPS** (DigitalOcean Droplet, ~$6/month) is the control plane: runs Headscale (self-hosted Tailscale coordination), executes Terraform for Proxmox VMs, and listens for GitHub webhooks to trigger automated deploys.

See [`docs/plan.md`](docs/plan.md) for full architecture, VM layout, and all decisions.

## Repo structure

```
terraform/
  modules/proxmox-vm/     # shared VM module (bpg/proxmox provider)
  nuc/                    # NUC root module — state in MinIO on Storinator
  anton/                  # Anton root module — state in MinIO on Storinator
  vps/                    # VPS root module — state is local file on operator laptop
ansible/
  roles/
    base/                 # all Debian VMs
    docker/               # Docker Compose VMs
    physical/             # physical devices (ansible-pull)
    headscale/            # VPS — Headscale + webhook listener
    network/              # Proxmox bridge config
  base.yml                # day-2 config for VMs (push)
  vps.yml                 # VPS bootstrap and config
  physical.yml            # physical device config (pull mode, targets localhost)
  tailscale.yml           # Tailscale install on physical nodes (points at Headscale)
services/
  dns/                    # AdGuard config (pre-seeded, no setup wizard)
  nuc-infra/              # Docker Compose — NUC infra VM
  anton/                  # Docker Compose — Anton services VM
scripts/
  deploy.sh               # terraform apply + ansible-playbook (called by webhook)
  deploy-services.sh      # docker compose pull + up -d on services VMs
  webhook-deploy.sh       # runs on VPS — detects changed paths, runs right commands
  bootstrap-physical.sh   # one-time bootstrap for a new physical device
  infisical-bootstrap.sh  # bootstraps Infisical after first apply
  jellyfin-init.sh        # headless Jellyfin setup via API
  servarr-init.sh         # links Prowlarr to Radarr/Sonarr
  calibre-init.sh         # sets Calibre-Web admin password
  n8n-init.sh             # creates n8n owner account
cloud-init/
  base.yaml               # base cloud-init for all VMs
  docker-host.yaml        # extended cloud-init for Docker Compose VMs
docs/
  plan.md                 # architecture plan and all decisions
  runbook.md              # step-by-step bootstrap guide
  hardware_inventory.md   # hardware reference
  TODOS.md                # deferred work items
```

## How deploys work

Push to `main` → GitHub webhook → VPS detects changed paths → runs:

| Changed path | Action |
|---|---|
| `terraform/nuc/` or `terraform/anton/` | `./scripts/deploy.sh` (Terraform + Ansible) |
| `ansible/` | `ansible-playbook base.yml` |
| `services/` | `./scripts/deploy-services.sh` |
| `ansible/physical.yml` or `ansible/roles/physical/` | Nothing — ansible-pull on each device picks it up within 30 min |
| `terraform/vps/` | Blocked — run `terraform apply` manually from operator laptop |

## Bootstrap

Full step-by-step guide in [`docs/runbook.md`](docs/runbook.md). High-level summary:

**Manual (one-time):**
1. Join Anton and NUC into a Proxmox cluster via UI
2. Create Proxmox API tokens on each node
3. Create NFS datasets + enable MinIO on Storinator (S3 state backend)
4. Provision VPS: `cd terraform/vps && terraform apply` from laptop
5. Bootstrap Headscale on VPS: `ansible-playbook ansible/vps.yml`

**Automated (from VPS thereafter):**
```bash
# Install Tailscale on physical nodes (points at Headscale)
ansible-playbook ansible/tailscale.yml

# Fill in terraform.tfvars, provision all VMs
./scripts/deploy.sh

# Bootstrap Infisical, add credentials to tfvars, re-deploy
./scripts/infisical-bootstrap.sh
./scripts/deploy.sh

# Create Vaultwarden account at https://vault.home (one manual step, ever)

# Seed secrets into Infisical UI, reboot VMs

# Configure GitHub webhook → all future changes deploy automatically
```

## Secrets

| Store | What | How populated |
|---|---|---|
| **`terraform.tfvars`** | Infrastructure credentials (Proxmox, Headscale key, MinIO, Infisical) | Manually, backed up in Vaultwarden |
| **Infisical** | Machine-consumed secrets: service API keys, inter-service tokens, developer API keys | Manually via Infisical UI |
| **Vaultwarden** | Human-consumed secrets: web UI admin passwords, personal credentials | Manually when setting up each service |

VMs fetch secrets from Infisical at boot via `infisical export` → ephemeral `.env` file.
Physical devices fetch their deploy key from Infisical during bootstrap.

Never commit `.env`, `terraform.tfvars`, or `*.tfstate`.

## Hardware

See [`docs/hardware_inventory.md`](docs/hardware_inventory.md).
