# homelab

Infrastructure-as-code for a Proxmox-based homelab. All compute infrastructure is defined in Terraform and reproducible from this repo.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Tailscale mesh                        │
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │    Anton     │   │     NUC      │   │   Storinator   │  │
│  │  (compute)   │   │   (infra)    │   │    (NAS)       │  │
│  │              │   │              │   │                │  │
│  │ • Ollama     │   │ • AdGuard    │   │ • TrueNAS      │  │
│  │ • Jellyfin*  │   │ • Traefik    │   │ • NFS exports  │  │
│  │ • Servarr*   │   │ • HA         │   │                │  │
│  │ • Monitoring*│   │ • Infisical  │   └────────────────┘  │
│  │ • n8n*       │   │ • Vaultwarden│   ┌────────────────┐  │
│  │ • OpenClaw*  │   │ • Obsidian   │   │   Gringotts    │  │
│  │              │   │ • Dashboard  │   │ (offsite backup│  │
│  │              │   │ • MinIO      │   │  TrueNAS)      │  │
│  └──────────────┘   └──────────────┘   └────────────────┘  │
│                                                             │
│  * migrates to services node when built                     │
└─────────────────────────────────────────────────────────────┘
```

See [`docs/plan.md`](docs/plan.md) for full architecture and decisions.

## Repo structure

```
terraform/
  modules/proxmox-vm/   # reusable VM module (bpg/proxmox)
  nuc/                  # NUC root module
  anton/                # Anton root module
services/
  nuc-infra/            # Docker Compose — NUC infra VM
  anton/                # Docker Compose — Anton services VM
cloud-init/
  base.yaml             # base cloud-init for all VMs
  docker-host.yaml      # cloud-init for Docker Compose VMs
docs/
  plan.md               # architecture plan and decisions
  hardware_inventory.md # hardware reference
  TODOS.md              # deferred work
```

## Bootstrap

Before running Terraform, complete the manual bootstrap steps in [`docs/plan.md`](docs/plan.md#bootstrap-phase-manual). In short:

1. Join Anton and NUC into a Proxmox cluster
2. Create Ubuntu cloud-init template on each node
3. Deploy MinIO on NUC (manual Docker run)
4. Deploy Infisical on NUC (manual Docker run), seed secrets
5. Install Tailscale on all physical nodes
6. Configure `terraform.tfvars` from the `.example` files

## Deploying

```bash
# NUC VMs
cd terraform/nuc
cp terraform.tfvars.example terraform.tfvars  # fill in values
terraform init
terraform apply

# Anton VMs
cd terraform/anton
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## Secrets

Secrets are managed by [Infisical](https://infisical.com) (self-hosted on NUC). Never commit `.env` files or `terraform.tfvars` — both are gitignored. Seed values are documented in Infisical under the `prod` environment.

## Hardware

See [`docs/hardware_inventory.md`](docs/hardware_inventory.md).
