# Services

Per-VM service inventory. All persistent data mounts to `/mnt/nas/docker/<service>` on
Alakazam NFS — VMs are stateless and can be rebuilt without data loss.

---

## Physical hosts

### alakazam-deploy (`192.168.0.7`)

TrueNAS SCALE KVM VM — not Proxmox-managed. Bootstrapped once via `scripts/bootstrap-alakazam-deploy.sh`.

| Tool | Notes |
|------|-------|
| Terraform | Provisions Diglett and Machamp VMs. State stored on Alakazam NFS (`/mnt/terraform-state`) |
| Ansible | Push-only config management for all VMs and physical nodes |

---

## Diglett VMs

### diglett-dns (`192.168.0.2`)

| Service | Notes |
|---------|-------|
| AdGuard Home | LAN DNS resolver. Pre-seeded config — no setup wizard. DNS rewrites: `*.wsh` → A `192.168.0.32`, `*.home` → A `192.168.0.32` |
| Headscale | Self-hosted Tailscale coordination server. Pushes AdGuard's address as the global DNS resolver to all tailnet members |
| cloudflared | Cloudflare Tunnel — exposes Headscale publicly without open ports or a static IP |
| Tailscale subnet router | Advertises `192.168.0.0/24` to the tailnet so remote devices can reach LAN IPs via `.wsh` |
| Tailscale exit node | Primary exit node for the tailnet |

### diglett-haos (`192.168.0.22`)

| Service | Notes |
|---------|-------|
| Home Assistant OS | Home automation. Restored from vzdump backup on first boot — not managed via cloud-init or Ansible |

---

## Machamp VMs

### machamp-infra (`192.168.0.32`)

| Service | Notes |
|---------|-------|
| Infisical | Machine-consumed secrets (service API keys, inter-service tokens). Each VM fetches secrets at boot via `infisical export` |
| Vaultwarden | Human-consumed secrets (web UI admin passwords). One manual browser registration at bootstrap; persists on NFS forever |
| Authentik | OIDC identity provider. SSO for Grafana, n8n, Headplane, and Headscale (configure OIDC clients post-deploy) |
| Litestream | Continuously streams the Vaultwarden SQLite WAL to Alakazam NFS |

### machamp-services (`192.168.0.30`)

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy. Port 80 (HTTP → HTTPS redirect) and port 443 (HTTPS). Serves both `*.home` and `*.wsh` on both entrypoints |
| step-ca | Local CA. Issues TLS certs for `*.wsh` and `*.home` via ACME; Traefik uses it as the cert resolver |
| Jellyfin | Media server. Quadro P2200 passthrough for hardware transcoding |
| Radarr | Movie library management |
| Sonarr | TV library management |
| Prowlarr | Indexer manager; linked to Radarr and Sonarr |
| PhotoPrism | Photo archive and browsing |
| Calibre-Web | Ebook server |
| n8n | Automation workflows |
| CouchDB | Obsidian LiveSync backend |
| Quartz | Read-only Obsidian vault web publishing |
| Homepage | Service dashboard |
| Prometheus | Metrics collection |
| Grafana | Metrics dashboards |
| Loki | Log aggregation |
| Promtail | Log shipping (scrapes Docker container logs) |

### machamp-dev (`192.168.0.31`)

| Service | Notes |
|---------|-------|
| development workstation | Personal development environment |
