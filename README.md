# homelab

Infrastructure-as-code for a Proxmox-based homelab. All compute is defined in Terraform and reproducible from this repo.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Headscale tailnet                               │
│                                                                         │
│  ┌───────────────┐   ┌───────────────┐   ┌─────────────┐   ┌─────────┐ │
│  │     Anton     │   │  Services     │   │    NUC      │   │Storinator│ │
│  │  (compute)    │   │   (node)      │   │  (infra)    │   │  (NAS)  │ │
│  │               │   │               │   │             │   │         │ │
│  │ • Ollama      │   │ • Traefik     │   │ • AdGuard   │   │• TrueNAS│ │
│  │ • OpenClaw    │   │ • Jellyfin    │   │ • Headscale │   │• NFS    │ │
│  │ • Dev workst. │   │ • Servarr     │   │ • cloudflrd │   │• MinIO  │ │
│  └───────────────┘   │ • PhotoPrism  │   │ • Infisical │   └─────────┘ │
│                      │ • n8n         │   │ • Vaultwdn  │   ┌─────────┐ │
│                      │ • Monitoring  │   │ • Deploy VM │   │Gringotts│ │
│                      │ • Obsidian    │   └─────────────┘   │(offsite)│ │
│                      │ • Quartz      │                     └─────────┘ │
│                      └───────────────┘                                  │
└─────────────────────────────────────────────────────────────────────────┘
                              ▲
                    Cloudflare Tunnel
                    (public Headscale endpoint,
                     no open ports / public IP)
```

**NUC** runs all infrastructure: AdGuard Home (DNS + LAN resolver), Headscale (self-hosted Tailscale coordination) behind a Cloudflare Tunnel, Infisical (machine secrets), Vaultwarden (human secrets), and the deploy VM (Terraform + Ansible).

**Anton** and the **services node** split compute workloads: GPU inference, personal tooling, and all Docker Compose services.

**Two-domain DNS**: services are exposed on `*.wsh` (Tailscale/HTTPS via step-ca local CA) and `*.home` (LAN/HTTP). AdGuard resolves `*.wsh` as a CNAME to the services VM's Tailscale MagicDNS name and `*.home` as an A record to its LAN IP. See [DNS Architecture in docs/plan.md](docs/plan.md) for details.

See [`docs/plan.md`](docs/plan.md) for full architecture, VM layout, and all decisions.

## Repo structure

```
terraform/
  modules/proxmox-vm/     # shared VM module (bpg/proxmox provider)
  nuc/                    # NUC root module — state in MinIO on Storinator
  anton/                  # Anton root module — state in MinIO on Storinator
  services/               # services node root module — state in MinIO on Storinator
ansible/
  inventory/
    hosts.py              # dynamic inventory script — reads network.yml
  roles/
    base/                 # all Debian VMs and physical devices
    docker/               # Docker Compose VMs
    network/              # Proxmox bridge config on physical nodes
  base.yml                # day-2 config for all VMs (push)
  physical.yml            # physical device config (push)
  tailscale.yml           # one-time Tailscale install on physical nodes
  network.yml             # static IP config for Proxmox nodes
services/
  dns/                    # AdGuard + Headscale + cloudflared (pre-seeded, no wizards)
  nuc-infra/              # Infisical + Vaultwarden + Litestream
  nuc-deploy/             # webhook listener for internal deploy triggers
  anton/                  # Docker Compose — all Anton/services workloads
network.yml               # single source of truth for all IPs and VM IDs
scripts/
  deploy.sh               # terraform apply + ansible-playbook
  deploy-services.sh      # docker compose pull + up -d on services VMs
  bootstrap-physical.sh   # one-time bootstrap for a new physical device
  jellyfin-init.sh        # headless Jellyfin setup via API
  servarr-init.sh         # links Prowlarr to Radarr/Sonarr
  calibre-init.sh         # sets Calibre-Web admin password
  n8n-init.sh             # creates n8n owner account
docs/
  plan.md                 # architecture plan and all decisions
  runbook.md              # step-by-step bootstrap guide
  hardware_inventory.md   # hardware reference
  TODOS.md                # deferred work items
```

## How deploys work

All deploys are manual, initiated from the deploy VM (`nuc-deploy`, `192.168.0.23`):

```bash
ssh debian@192.168.0.23
cd ~/homelab && git pull

./scripts/deploy.sh           # terraform apply + ansible for all nodes
./scripts/deploy.sh nuc       # single node
./scripts/deploy-services.sh  # docker compose only, no terraform
```

`network.yml` is the single source of truth for all IPs and VM IDs. The dynamic inventory script (`ansible/inventory/hosts.py`) reads it directly — no separate hosts file to maintain.

## Bootstrap

Full step-by-step guide in [`docs/runbook.md`](docs/runbook.md). High-level summary:

**Phase 1 — Physical setup (one-time, manual):**
1. Join Anton, NUC, and services node into a Proxmox cluster via UI
2. Create Proxmox API tokens on each node
3. Create NFS datasets + enable MinIO on Storinator (S3 state backend)
4. Configure static IPs on physical nodes via Ansible

**Phase 2 — Bootstrap the deploy VM (from operator laptop):**
```bash
cp terraform/nuc/terraform.tfvars.example terraform/nuc/terraform.tfvars
# fill in Proxmox tokens, MinIO creds, SSH key, Cloudflare API token
cd terraform/nuc && terraform apply -target=module.deploy
ansible-playbook ansible/bootstrap-deploy.yml
```

**Phase 3 — Full deployment (from the deploy VM):**
```bash
ssh debian@192.168.0.23 && cd ~/homelab

# DNS VM first (Headscale must exist before other VMs get Tailscale keys)
cd terraform/nuc && terraform apply -target=module.dns
ansible-playbook ansible/bootstrap-headscale.yml  # generates + writes pre-auth key

# All remaining VMs
./scripts/deploy.sh

# Bootstrap Infisical, distribute credentials, bring up all services
ansible-playbook ansible/bootstrap-infisical.yml
ansible-playbook ansible/site.yml
```

**Phase 4 — Post-bootstrap:**
- Trust the step-ca root CA on personal devices
- Add external API keys (Anthropic, OpenAI, GitHub) to Infisical via UI
- Back up `terraform.tfvars` to Vaultwarden

## Secrets

| Store | What | How populated |
|---|---|---|
| **`terraform.tfvars`** | Infrastructure credentials (Proxmox tokens, MinIO, SSH key, Cloudflare API token, Headscale pre-auth key) | Manually; `bootstrap-headscale.yml` writes the pre-auth key automatically |
| **Infisical** | Machine-consumed secrets: service API keys, inter-service tokens, developer API keys | Auto-seeded per service by `ansible/site.yml`; external keys added via UI |
| **Vaultwarden** | Human-consumed secrets: web UI admin passwords, personal credentials | Written by each service's Ansible role after configuration |

VMs fetch machine secrets from Infisical at boot via `infisical export` → ephemeral `.env` file.
Infisical machine identity credentials live at `/etc/infisical.env` on each VM (root-owned, mode 0600), written by `ansible/bootstrap-infisical.yml`.

Never commit `.env`, `terraform.tfvars`, or `*.tfstate`.

## Hardware

See [`docs/hardware_inventory.md`](docs/hardware_inventory.md).
