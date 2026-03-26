# CLAUDE.md

Guidelines for working in this repo.

## What this repo is

Infrastructure-as-code for a personal homelab. Proxmox + Terraform for compute, Docker Compose for services, Infisical for secrets. See `docs/plan.md` for full architecture.

## Key conventions

- **Terraform provider**: `bpg/proxmox` (not `telmate/proxmox`)
- **Secret references**: never hardcode secrets. All secrets come from Infisical via the `infisical_secrets` data source. Use `var.*` for provider credentials (passed via `terraform.tfvars`, gitignored).
- **VM IDs**: NUC VMs use 200–299, Anton VMs use 100–199. Reserve 300+ for the services node.
- **IP addresses**: NUC VMs use 192.168.0.20–29, Anton VMs use 192.168.0.10–19.
- **Docker Compose**: persistent data always mounts to `/mnt/nas/<dataset>/<service>` (Storinator NFS). Never use named volumes for stateful data — it must survive VM recreation.
- **Traefik routing**: every service gets a `traefik.http.routers.<name>.rule=Host('<name>.home')` label. Use `websecure` entrypoint with the `letsencrypt` cert resolver.
- **Headless config**: all services are configured without the web UI. See the "Headless Service Configuration" section in `docs/plan.md` for the strategy per service.

## Repo structure

```
terraform/modules/proxmox-vm/  — shared VM module, edit here for VM-level changes
terraform/nuc/                 — NUC VMs (DNS, HAOS, Infisical)
terraform/anton/               — Anton VMs (Ollama, OpenClaw, Ubuntu, services)
services/dns/                  — AdGuard config (pre-seeded AdGuardHome.yaml)
services/nuc-infra/            — Docker Compose for NUC infra VM
services/anton/                — Docker Compose for Anton services VM
scripts/                       — bootstrap and init scripts (headless service setup)
cloud-init/                    — cloud-init templates
docs/                          — architecture docs, plan, TODOs
```

## Adding a new service

1. Add it to the appropriate `services/<node>/docker-compose.yml`
2. Add Traefik labels
3. Mount persistent data to `/mnt/nas/docker/<service>`
4. Add any required secrets to Infisical under `/nuc` or `/anton` folder
5. Add the secret reference to the `.env.example`
6. If the service requires first-boot setup, add a headless init script under `scripts/`

## Adding a new VM

1. Add a `module "<name>"` block in `terraform/<node>/main.tf` using the `proxmox-vm` module
2. Assign a VM ID and IP from the node's reserved range
3. Add any node-specific secrets to Infisical
4. Run `terraform plan` to verify before applying

## Things to avoid

- Don't commit `terraform.tfvars`, `.env`, `*.tfstate`, or any file containing real credentials
- Don't use the `telmate/proxmox` provider — use `bpg/proxmox`
- Don't store persistent service data in Docker named volumes — use NFS mounts
- Don't add services directly to physical nodes — everything runs in VMs
- Don't require web UI interaction for first-boot service setup — use pre-seeded configs or init scripts
