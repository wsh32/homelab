# TODOs

Pending work items. Ordered roughly by priority within each section.

---

## Infrastructure

### HAOS VM in Terraform

**What:** Manage `diglett-haos` (VM ID 202) via Terraform like the other VMs.

**Blocker:** HAOS image releases use `.qcow2.xz` compression. The `bpg/proxmox` provider's
`proxmox_download_file` only supports gz/lzo/zst/bz2 — not xz. Proxmox itself also rejects
`.qcow2.xz` as a valid import filename.

**Options:**
- Wait for `bpg/proxmox` to add xz support
- Pre-download and decompress on the Proxmox host via a `null_resource` + remote-exec, then reference the `.qcow2` file directly
- Use a `local-exec` to decompress locally and upload via SCP

**For now:** Create manually:
```bash
# On diglett (ssh root@192.168.0.6)
wget -O /tmp/haos.qcow2.xz https://github.com/home-assistant/operating-system/releases/download/17.3/haos_ova-17.3.qcow2.xz
xz -d /tmp/haos.qcow2.xz
# Then create VM via Proxmox UI: VM ID 202, 2 cores, 4GB RAM, import disk from /tmp/haos.qcow2
# Restore config from vzdump backup after first boot.
```

### Cloudflare Tunnel (Terraform)

**What:** Add Cloudflare provider to Terraform for the Headscale public tunnel.

**Work:**
- Add `cloudflare/cloudflare` provider to `terraform/diglett/versions.tf`
- Add `cloudflare_api_token` to `variables.tf` and `terraform.tfvars.example`
- Add `cloudflare_tunnel` + `cloudflare_tunnel_config` + `cloudflare_record` resources for Headscale
- Pass the tunnel token output into the DNS VM module via cloud-init (writes to cloudflared env file)
- Add `headscale_url` variable to `terraform/modules/proxmox-vm/` and thread it through all VM definitions for Tailscale `--login-server`

### PostgreSQL 16 → 17 Upgrade

**What:** Upgrade the shared PostgreSQL instance from 16 to 17. PG16 is EOL Nov 2025.

**Work:** During a maintenance window:
```bash
docker exec postgres pg_dumpall -U postgres | gzip > /tmp/pgdump.sql.gz
# Update image to postgres:17-alpine in docker-compose.yml
# Wipe /var/lib/postgres, restart, restore from dump
```
The NFS `postgres-backup` daily dump can serve as the dump source.

### Proxmox vzdump Backup Schedules

**What:** Add Terraform resources for automated VM backups.

**Work:** Add `proxmox_virtual_environment_schedule` (or equivalent `bpg/proxmox` resource) Terraform resources for HAOS daily backup and all other VMs weekly backup, targeting the Alakazam `backups` NFS dataset.

### Internal Bridge Network Isolation (vmbr1)

**What:** Create a Proxmox internal bridge (`vmbr1`) on machamp and attach machamp-infra and machamp-media to it, so Traefik can reach service backends without those ports being exposed on the LAN.

**Why:** Service ports (Jellyfin :8096, Radarr :7878, etc.) currently bind on all interfaces (`0.0.0.0`), meaning any LAN device can hit them directly and bypass Traefik forwardAuth / Authentik.

**Work:**
1. Add `vmbr1` internal bridge to `/etc/network/interfaces` on machamp via `blockinfile` in `ansible/roles/proxmox/tasks/main.yml`
2. Add `internal_bridge: vmbr1` and `internal_ip` fields to machamp nodes in `network.yml`
3. Extend Terraform module with optional `internal_ip` variable; add second NIC + `ip_config` block
4. Change all port bindings in `services/machamp-media/docker-compose.yml` from `PORT:PORT` to `10.0.0.2:PORT:PORT`
5. Traefik backends in `services-vm.yml.j2` template update to use `internal_ip` when present

**Note:** VM-recreation event for machamp-infra and machamp-media. Depends on all services deployed and working.

---

## Security & Networking

### UFW Firewall Hardening

**What:** Enable UFW on all VMs with a default-deny policy and per-role allowlists.

**Why:** Currently no host firewall is configured. All ports are open on the LAN.

**Minimum policy per role:**
- All VMs: allow SSH (22)
- `services` VMs: allow Docker bridge traffic
- `diglett-dns`: allow DNS (53 TCP/UDP), AdGuard UI (3000 TCP) from LAN
- `machamp-media`: allow Traefik (80, 443) from LAN and Tailscale
- `diglett-infra`: allow Infisical (8080), Vaultwarden (80), and Authentik (9000) from LAN/Tailscale

**Note:** Add UFW tasks back to `ansible/roles/base/tasks/main.yml` and per-role allowlists to each service role. The base role previously had UFW enabled — removed to unblock initial bring-up.

### Tailscale ACL Segmentation

**What:** Add role-based ACL policy via the `tailscale_acl` Terraform resource.

**Why:** All nodes currently communicate freely over Tailscale with no segmentation. A compromised container has lateral movement to every node.

**Minimum policy:**
- Tag nodes by role (infra, compute, storage, backup)
- Restrict Ditto to replication traffic from Alakazam only
- Restrict Proxmox API ports to operator machine

### Tailscale `.wsh` IP Allowlist Middleware

**Status:** `.wsh` routers are live. One remaining item:

- Add Traefik IP allowlist middleware restricting `traefik.wsh`, `prometheus.wsh`, `couchdb.wsh` to `100.64.0.0/10` (Tailscale CGNAT only — no open LAN exposure for admin/internal services)

### Backup DNS VM

**What:** Deploy a secondary AdGuard Home instance as a backup DNS VM.

**Why:** The primary DNS VM on Diglett is a single point of failure. Currently mitigated by 8.8.8.8 as fallback, but that bypasses ad-blocking and breaks `.home` domain resolution.

---

## Access Control

### OIDC for Grafana and n8n

**What:** Wire up Grafana and n8n as OIDC clients in Authentik.

**Work:**
- Add OIDC environment variables to Grafana and n8n in `services/machamp-media/docker-compose.yml`
- Bootstrap OAuth2 providers and applications in Authentik via API (add to `ansible/roles/infra/tasks/main.yml`)
- Write client secrets to Infisical

**Note:** Headscale, Headplane, Jellyfin, and Seerr OIDC are already done.

### Authentik User Groups and Access Control

**What:** Define `grunts` and `executives` groups in Authentik, bind them to applications, and mirror the segmentation in Headscale ACLs.

**Groups:**
- `executives` — admins. Full access to all services and Headscale enrollment.
- `grunts` — regular/guest users. Headscale enrollment + media services only.

**Authentik application bindings:**
| Application | executives | grunts |
|---|---|---|
| Headscale OIDC | ✓ | ✓ |
| Headplane | ✓ | ✗ |
| Grafana | ✓ (admin role) | ✗ |
| n8n | ✓ | ✗ |
| Jellyfin | ✓ | ✓ |
| Calibre-Web | ✓ | ✓ |
| PhotoPrism | ✓ | ✓ |

**Headscale ACL changes (`acls.hujson`):**
- `executives` → access to all tailnet hosts and ports
- `grunts` → access to the services VM on media ports only (Jellyfin :8096, Calibre-Web :8083, PhotoPrism :2342)

**Work:**
1. Add Authentik group bootstrap tasks to `ansible/roles/infra/tasks/main.yml`
2. Update `services/diglett-dns/headscale/acls.hujson` with group-based ACL rules

**Depends on:** Grafana/n8n OIDC done above.

---

## Services

### GPU Passthrough: Machamp Host Setup

**What:** Configure Machamp host for VFIO GPU passthrough.

**Work:** On Machamp host, add `amd_iommu=on` to GRUB kernel params, load VFIO modules, bind the Quadro P2200 to VFIO before Proxmox claims it; document exact PCI addresses in `docs/hardware_inventory.md`.

**Note:** Module extension in Terraform is already done (`hostpci_devices` variable). Once PCI address is confirmed (`ssh root@machamp lspci | grep -i quadro`), fill in `services_gpu_pci_ids` in `terraform/machamp/terraform.tfvars`.

### Radarr/Sonarr Quality Profiles

**What:** Configure quality profiles via the arr API in the init roles instead of manually through the UI.

**Desired settings:**
- **Movies (Radarr):** cutoff WEB-2160p, allow up to 4K WEB/Bluray, exclude Remux, max ~50 GB for 4K / ~15 GB for 1080p
- **TV (Sonarr):** cutoff WEB-1080p, allow up to 1080p WEB/Bluray, exclude Remux, max ~4 GB per episode

**Work:**
1. Fetch the default quality profile to get quality IDs (`GET /api/v3/qualityprofile/1`)
2. Add a `PUT /api/v3/qualityprofile/{{ id }}` task in `roles/radarr-init` and `roles/sonarr-init` with desired `items` and `cutoff`

### Quartz (Notes) Approach

**What:** Resolve how to run Quartz as a live web service.

**Why:** `ghcr.io/jackyzha0/quartz:v4` doesn't exist as a runnable web server image — Quartz is a static site generator, not a server.

**Options:**
- Build the site in CI and serve the output with nginx
- Run a Quartz build container on a cron and serve the output with nginx
- Use a different publishing approach

Update `services/machamp-media/docker-compose.yml` once decided.

### node_exporter

**What:** Deploy `prom/node-exporter` on each service-running VM.

**Work:** Add to each service docker-compose stack (or as a standalone compose file on each VM); verify all targets appear green in Prometheus.

### NUT/UPS Integration

**What:** Configure NUT server on Orange Pi and NUT clients on Machamp, Diglett, and Alakazam.

**Work:**
- Add Orange Pi to `network.yml` (type: other, assign IP in `.4–.19` range)
- Write `ansible/roles/nut/` that installs and configures NUT
- Add to `ansible/physical.yml` and relevant VM playbooks

---

## Operations

### NFS Export Strategy

**What:** Formalize which Alakazam datasets get NFS-exported, to what clients, and with what permissions.

**Context:** Alakazam datasets: `backups`, `media`, `docker`, `apps/terraform`, `photos`, `lightroom`. Each needs a defined NFS export policy (which VMs, read-only vs read-write). All mounts currently use `soft,timeo=30` options.

### Offline Credential Backup

**What:** Maintain an encrypted offline copy of critical credentials outside the homelab.

**Contents:**
- `terraform.tfvars` (Proxmox API token, Headscale pre-auth key)
- Infisical secrets export (all service runtime secrets)
- Proxmox root credentials
- `pvecm expected 1` quorum recovery command

**Why:** If Diglett dies, running containers on Machamp survive but new deploys are blocked until Infisical returns.

**Storage:** Encrypted file in a password manager on phone, or USB drive.

### External Uptime Monitor

**What:** Deploy Uptime Kuma on the Orange Pi or use a cloud ping service to monitor critical services externally.

**Why:** When Alakazam NFS hangs, the monitoring stack (Prometheus + Grafana on Machamp) also goes down. An external monitor outside the NFS blast radius can detect and alert on this.

### Ansible Multi-OS Support

**What:** Handle OS differences in Ansible roles (at minimum: SSH service name differs between Ubuntu `ssh` and Arch `sshd`).

**Depends on:** Actually adding a non-Ubuntu VM.
