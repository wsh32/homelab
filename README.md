# homelab

Infrastructure-as-code for a Proxmox-based homelab. All compute is defined in Terraform and reproducible from this repo.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Headscale tailnet                         │
│                                                                 │
│  ┌──────────────────┐            ┌──────────────────┐           │
│  │      Machamp       │            │    Diglett      │           │
│  │                  │            │                  │           │
│  │  GPU compute +   │            │  Always-on       │           │
│  │  all services    │            │  infrastructure  │           │
│  └──────────────────┘            └────────┬─────────┘           │
│                                           │ Cloudflare Tunnel   │
│  ┌──────────────────┐            ┌────────▼─────────┐           │
│  │   Ditto      │            │    Alakazam     │           │
│  │  (offsite NAS)   │◄──replicate│  TrueNAS NAS      │           │
│  └──────────────────┘            │     TrueNAS NFS   │           │
│                                  └──────────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

| Node | Role |
|------|------|
| **Machamp** | Proxmox compute node. Hosts all VMs: GPU inference (Ollama, RTX 3060), personal tooling (OpenClaw, development workstation), and all Docker Compose services (Traefik, Jellyfin, Servarr, etc.) |
| **Diglett** | Always-on Proxmox infrastructure node. Hosts DNS (AdGuard Home), Tailscale coordination (Headscale behind Cloudflare Tunnel), secrets (Infisical + Vaultwarden), and the deploy VM |
| **Alakazam** | TrueNAS NAS. Provides NFS mounts for all persistent Docker volumes and Terraform state |
| **Ditto** | Offsite TrueNAS NAS. Receives daily/weekly ZFS replication from Alakazam; only reachable over Tailscale |
| **Orange Pi** | Miscellaneous device (role TBD) |

See [`docs/services.md`](docs/services.md) for the full per-VM service list.

## Repo structure

```
terraform/
  modules/proxmox-vm/     # shared VM module (bpg/proxmox provider)
  diglett/               # Diglett root module — state on Alakazam NFS
  machamp/                  # Machamp root module — state on Alakazam NFS
  services/               # services node root module — state on Alakazam NFS
ansible/
  inventory/
    homelab.py            # dynamic inventory script — reads network.yml
  roles/
    base/                 # all Ubuntu VMs and physical devices
    docker/               # Docker Compose VMs
    dns/                  # deploys services/dns/ stack to diglett-dns
    network/              # Proxmox bridge config on physical nodes
  base.yml                # day-2 config for all VMs (push)
  dns.yml                 # deploy AdGuard Home + Headscale + cloudflared
  physical.yml            # physical device config (push)
  tailscale.yml           # one-time Tailscale install on physical nodes
  network.yml             # static IP config for Proxmox nodes
services/
  dns/                    # AdGuard + Headscale + cloudflared (pre-seeded, no wizards)
  diglett-infra/         # Infisical + Vaultwarden + Litestream
  diglett-deploy/        # (not yet created)
  machamp/                  # Docker Compose — all Machamp/services workloads
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

All deploys are manual, initiated from the deploy VM (`alakazam-deploy`, `192.168.0.20`):

```bash
ssh ubuntu@192.168.0.20
cd ~/homelab && git pull

./scripts/deploy.sh           # terraform apply + ansible for all nodes
./scripts/deploy.sh diglett  # single node
./scripts/deploy-services.sh  # docker compose only, no terraform
```

`network.yml` is the single source of truth for all IPs and VM IDs. The dynamic inventory script (`ansible/inventory/homelab.py`) reads it directly — no separate hosts file to maintain.

## Bootstrap

Full step-by-step guide in [`docs/runbook.md`](docs/runbook.md). High-level summary:

**Phase 1 — Physical setup (one-time, manual):**
1. Form the Proxmox cluster (Machamp + Diglett) via the UI
2. Create Proxmox API tokens on each node; enable Snippets on `local` storage
3. Create NFS datasets on Alakazam (`apps/terraform`, `docker`); configure NFS shares with Maproot User: root
4. Configure static IPs on physical nodes via Ansible; set static IPs on Alakazam and Ditto via TrueNAS UI

**Phase 2 — Bootstrap the deploy VM (from operator laptop):**

The deploy VM (`alakazam-deploy`, `192.168.0.20`) is a TrueNAS SCALE KVM VM — not Terraform-managed. Create it manually in the TrueNAS UI, then:
```bash
# Fill in terraform.tfvars on your laptop first
cp terraform/diglett/terraform.tfvars.example terraform/diglett/terraform.tfvars
cp terraform/machamp/terraform.tfvars.example terraform/machamp/terraform.tfvars
# fill in Proxmox tokens, SSH key, Cloudflare API token

# Bootstrap the VM (installs Terraform, Ansible, Tailscale, Infisical CLI; sets up NFS mount)
ssh ubuntu@192.168.0.20 TAILSCALE_AUTH_KEY=<key> bash -s < scripts/bootstrap-alakazam-deploy.sh

# Copy tfvars to the deploy VM
scp terraform/diglett/terraform.tfvars ubuntu@192.168.0.20:~/homelab/terraform/diglett/
scp terraform/machamp/terraform.tfvars ubuntu@192.168.0.20:~/homelab/terraform/machamp/
```

**Phase 3 — Full deployment (from the deploy VM):**
```bash
ssh ubuntu@192.168.0.20
cd ~/homelab

# DNS VM first (Headscale must be running before other VMs register)
cd terraform/diglett && terraform init && terraform apply -target=module.dns
ansible-playbook ansible/dns.yml                  # deploys AdGuard + Headscale + cloudflared
ansible-playbook ansible/bootstrap-headscale.yml  # generates + writes Headscale pre-auth key

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
| **`terraform.tfvars`** | Infrastructure credentials (Proxmox tokens, SSH key, Cloudflare API token, Headscale pre-auth key) | Manually; `bootstrap-headscale.yml` writes the pre-auth key automatically |
| **Infisical** | Machine-consumed secrets: service API keys, inter-service tokens, developer API keys | Auto-seeded per service by `ansible/site.yml`; external keys added via UI |
| **Vaultwarden** | Human-consumed secrets: web UI admin passwords, personal credentials | Written by each service's Ansible role after configuration |

VMs fetch machine secrets from Infisical at boot via `infisical export` → ephemeral `.env` file.
Infisical machine identity credentials live at `/etc/infisical.env` on each VM (root-owned, mode 0600), written by `ansible/bootstrap-infisical.yml`.

Never commit `.env`, `terraform.tfvars`, or `*.tfstate`.

## Hardware

See [`docs/hardware_inventory.md`](docs/hardware_inventory.md).
