# CLAUDE.md

Guidelines for working in this repo.

## What this repo is

Infrastructure-as-code for a personal homelab. Proxmox + Terraform for compute, Docker Compose for services, three-tier secret management (terraform.tfvars / Infisical / Vaultwarden). See `docs/plan.md` for full architecture.

## Key conventions

- **Terraform provider**: `bpg/proxmox` (not `telmate/proxmox`)
- **Secrets**:
  - Machine-consumed secrets (service API keys, inter-service tokens) → Infisical. Fetched at VM boot via `infisical export` to generate an ephemeral `.env` file. Seeded by each service's Ansible role at bring-up time. Never hardcoded, never in `terraform.tfvars`.
  - Human-consumed secrets (web UI admin passwords) → Vaultwarden. Stored by each service's Ansible role after configuration. Never in Infisical.
  - Infrastructure credentials (Proxmox API tokens, SSH key, Cloudflare API token) → `var.*` from `terraform.tfvars`, gitignored. Lives on the deploy VM.
  - Infisical bootstrap secrets (MongoDB password, auth/encryption keys, Vaultwarden token, Authentik keys) → `/etc/homelab.env` on diglett-infra (root:root, 0600). Generated once by the `infra` Ansible role; NFS-persisted at `/mnt/nas/docker/infisical-backups/.secrets.env` for rebuild safety. Deploy + bootstrap: `INFISICAL_ADMIN_PASSWORD=<pass> ansible-playbook ansible/infra.yml`.
  - Developer API keys (Claude, Codex, GitHub) → Infisical, entered manually via UI, accessed via `infisical run --` on the operator laptop.
- **VM IDs**: Diglett VMs use 200–299, Machamp VMs use 100–199.
- **IP addresses**: physical nodes use 192.168.0.4–19 (`.7` = alakazam-deploy), diglett-dns VM is special-cased at `.2`, Diglett VMs use 192.168.0.20–29, Machamp VMs use 192.168.0.30–49.
- **Docker Compose**: persistent data always mounts to `/mnt/nas/<dataset>/<service>` (Alakazam NFS). Never use named volumes for stateful data -- it must survive VM recreation.
- **Traefik routing**: Traefik runs on `diglett-infra` (192.168.0.20). Services co-located on diglett-infra use Docker Compose labels. Services on other VMs are declared as external backends via `ansible/roles/infra/templates/services-vm.yml.j2` — rendered by Ansible from `network.yml` at deploy time. Do not edit the rendered file on the VM directly. Both `.home` (LAN) and `.wsh` (Tailscale) routers are generated for each service. Current label pattern for co-located services:
  ```yaml
  - "traefik.http.routers.<name>-home.rule=Host(`<name>.home`)"
  - "traefik.http.routers.<name>-home.entrypoints=web"
  - "traefik.http.routers.<name>-home-tls.rule=Host(`<name>.home`)"
  - "traefik.http.routers.<name>-home-tls.entrypoints=websecure"
  - "traefik.http.routers.<name>-home-tls.tls=true"
  - "traefik.http.routers.<name>-home-tls.tls.certresolver=step"
  - "traefik.http.services.<name>-svc.loadbalancer.server.port=<port>"
  ```
  TLS cert resolver is `step` (local step-ca CA), not `letsencrypt`. Both HTTP and HTTPS
  are served on `.home` -- devices with the step-ca root cert installed get HTTPS, others
  fall back to HTTP.
- **Headless config**: all services are configured without the web UI. Two accepted exceptions: HAOS (restored from backup) and Vaultwarden (one manual browser registration). See "Headless Service Configuration" in `docs/plan.md`.

## Repo structure

```
terraform/modules/proxmox-vm/  -- shared VM module, edit here for VM-level changes
terraform/diglett/             -- Diglett VMs (DNS, HAOS)
terraform/machamp/             -- Machamp VMs (Infra, Services, Dev)
services/diglett-dns/          -- AdGuard Home + Headscale + cloudflared
services/diglett-infra/        -- Infisical + Vaultwarden + Authentik + Litestream + Traefik
services/machamp-media/     -- all Docker Compose services (Jellyfin, Grafana, etc.)
scripts/                       -- bootstrap and init scripts (headless service setup)
ansible/                       -- push-only config management for VMs and physical devices
docs/                          -- architecture docs, plan, TODOs
```

## Adding a new service

1. Add a service entry to `network.yml` under the appropriate VM's `services:` list:
   ```yaml
   - name: myservice
     port: 1234
     nfs_data: docker/myservice   # NFS mount path under /mnt/nas/
     authentik: proxy             # none | proxy (forwardAuth) | oidc
   ```
2. Add the container definition to `services/<vm>/docker-compose.yml`
3. Add any machine-consumed secrets (API keys, tokens) to Infisical
4. Add any web UI admin passwords to Vaultwarden manually after first boot
5. If the service requires first-boot setup, add an Ansible init role under `ansible/roles/<service>-init/`

Traefik routing (`.home` and `.wsh` routers + backend) is automatically generated from
`network.yml` when `ansible/infra.yml` runs. No manual edits to `services-vm.yml`.

## Adding a new VM

1. Add a `module "<name>"` block in `terraform/<node>/main.tf` using the `proxmox-vm` module
2. Assign a VM ID and IP from the node's reserved range
3. Run `terraform plan` to verify before applying

## Headless-first problem solving

Before suggesting or implementing any step that requires manual web UI interaction, exhaustively explore headless alternatives:

- **Pre-seeded config files**: write config files to the NFS volume before the container starts (e.g. `qBittorrent.conf`, `config.ini`, `encoding.xml`)
- **REST API / `uri` module**: most services expose an API -- use it from Ansible with idempotent check-then-write patterns
- **Direct database writes**: if an app's setup API endpoint is broken or incompatible (e.g. Seerr's `POST /api/v1/auth/jellyfin` requiring unauthenticated Jellyfin access), write directly to the service's SQLite or config files, then restart the container
- **Environment variables**: many services accept first-boot config via env vars; prefer these over post-start API calls where available
- **Init containers / one-shot tasks**: use `community.docker.docker_container` with `detach: false` and `cleanup: true` for one-shot setup commands (e.g. Recyclarr)

Only accept a manual step if none of the above apply AND the service is in the explicit exceptions list (HAOS, Vaultwarden). When blocked by an app's broken or missing API, find the data store it reads from and write there directly.

## Ansible task naming

- Task names describe **what** the task does, not why it exists or who it's for. No parenthetical context like `(migration for existing installs)`, `(idempotent)`, `(first run only)`, etc.

## Things to avoid

- Don't commit `terraform.tfvars`, `.env`, `*.tfstate`, or any file containing real credentials
- Don't use the `telmate/proxmox` provider -- use `bpg/proxmox`
- Don't store persistent service data in Docker named volumes -- use NFS mounts
- Don't add services directly to physical nodes -- everything runs in VMs
- Don't put human-consumed passwords (web UI logins) in Infisical -- those go in Vaultwarden
- Don't put machine-consumed secrets (API keys, tokens) in Vaultwarden -- those go in Infisical
- Don't hardcode secrets or generate them with `random_password` in Terraform -- use Infisical
- Don't require web UI interaction for first-boot service setup -- use pre-seeded configs or init scripts (exceptions: HAOS, Vaultwarden)
