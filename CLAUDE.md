# CLAUDE.md

Guidelines for working in this repo.

## What this repo is

Infrastructure-as-code for a personal homelab. Proxmox + Terraform for compute, Docker Compose for services, three-tier secret management (terraform.tfvars / Infisical / Vaultwarden). See `docs/plan.md` for full architecture.

## Key conventions

- **Terraform provider**: `bpg/proxmox` (not `telmate/proxmox`)
- **Secrets**:
  - Machine-consumed secrets (service API keys, inter-service tokens) → Infisical. Fetched at VM boot via `infisical export` to generate an ephemeral `.env` file. Never hardcoded, never in `terraform.tfvars`.
  - Human-consumed secrets (web UI admin passwords) → Vaultwarden. Set manually when configuring a service. Never in Infisical.
  - Infrastructure credentials (Proxmox, Tailscale, Infisical, Vaultwarden master password) → `var.*` from `terraform.tfvars`, gitignored.
  - Developer API keys (Claude, Codex, GitHub) → Infisical, entered via UI, accessed via `infisical run --` on the operator laptop.
- **VM IDs**: NUC VMs use 200–299, Anton VMs use 100–199, services node VMs use 300–399.
- **IP addresses**: Anton VMs use 192.168.0.10–19, NUC VMs use 192.168.0.20–29, services node VMs use 192.168.0.30–39. Physical nodes use 192.168.0.2–9.
- **Docker Compose**: persistent data always mounts to `/mnt/nas/<dataset>/<service>` (Storinator NFS). Never use named volumes for stateful data — it must survive VM recreation.
- **Traefik routing**: each service gets two routers — `<name>-wsh` (Tailscale, HTTPS) and `<name>-home` (LAN, HTTP). Omit a router to restrict exposure on that network. Default is both. See DNS Architecture in `docs/plan.md` for the full two-domain design.
  ```yaml
  - "traefik.http.routers.<name>-wsh.rule=Host(`<name>.wsh`)"
  - "traefik.http.routers.<name>-wsh.entrypoints=websecure"
  - "traefik.http.routers.<name>-wsh.tls=true"
  - "traefik.http.routers.<name>-home.rule=Host(`<name>.home`)"
  - "traefik.http.routers.<name>-home.entrypoints=web"
  - "traefik.http.services.<name>-svc.loadbalancer.server.port=<port>"
  ```
  TLS cert resolver is `step` (local step-ca CA), not `letsencrypt`.
- **Headless config**: all services are configured without the web UI. Two accepted exceptions: HAOS (restored from backup) and Vaultwarden (one manual browser registration). See "Headless Service Configuration" in `docs/plan.md`.

## Repo structure

```
terraform/modules/proxmox-vm/  — shared VM module, edit here for VM-level changes
terraform/nuc/                 — NUC VMs (DNS, HAOS, Infisical, Deploy)
terraform/anton/               — Anton VMs (Ollama, OpenClaw, Debian, Services)
terraform/vps/                 — DigitalOcean VPS (operator laptop only)
services/dns/                  — AdGuard Home (pre-seeded AdGuardHome.yaml)
services/nuc-infra/            — Infisical + Vaultwarden + Litestream
services/nuc-deploy/           — internal webhook listener (adnanh/webhook)
services/anton/                — all Docker Compose services (Traefik, Jellyfin, etc.)
services/vps/                  — Headscale + GitHub webhook forwarder
scripts/                       — bootstrap and init scripts (headless service setup)
ansible/                       — push-only config management for VMs, physical devices, VPS
docs/                          — architecture docs, plan, TODOs
```

## Adding a new service

1. Add it to the appropriate `services/<node>/docker-compose.yml`
2. Add Traefik labels
3. Mount persistent data to `/mnt/nas/docker/<service>`
4. Add any machine-consumed secrets (API keys, tokens) to Infisical
5. Add any web UI admin passwords to Vaultwarden manually after first boot
6. If the service requires first-boot setup, add a headless init script under `scripts/`

## Adding a new VM

1. Add a `module "<name>"` block in `terraform/<node>/main.tf` using the `proxmox-vm` module
2. Assign a VM ID and IP from the node's reserved range
3. Run `terraform plan` to verify before applying

## Things to avoid

- Don't commit `terraform.tfvars`, `.env`, `*.tfstate`, or any file containing real credentials
- Don't use the `telmate/proxmox` provider — use `bpg/proxmox`
- Don't store persistent service data in Docker named volumes — use NFS mounts
- Don't add services directly to physical nodes — everything runs in VMs
- Don't put human-consumed passwords (web UI logins) in Infisical — those go in Vaultwarden
- Don't put machine-consumed secrets (API keys, tokens) in Vaultwarden — those go in Infisical
- Don't hardcode secrets or generate them with `random_password` in Terraform — use Infisical
- Don't require web UI interaction for first-boot service setup — use pre-seeded configs or init scripts (exceptions: HAOS, Vaultwarden)
