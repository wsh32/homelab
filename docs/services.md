# Services

Per-VM service inventory. All persistent data mounts to `/mnt/nas/docker/<service>` on
Storinator NFS — VMs are stateless and can be rebuilt without data loss.

---

## NUC VMs

### nuc-dns (`192.168.0.2`)

| Service | Notes |
|---------|-------|
| AdGuard Home | LAN DNS resolver. Pre-seeded config — no setup wizard. DNS rewrites: `*.wsh` → CNAME `anton-services.ts.home`, `*.home` → A `192.168.0.31` |
| Headscale | Self-hosted Tailscale coordination server. Pushes AdGuard's Tailscale IP as the DNS resolver for `.wsh` and `.home` to all tailnet members |
| cloudflared | Cloudflare Tunnel — exposes Headscale publicly without open ports or a static IP |
| Tailscale exit node | Primary exit node for the tailnet |

### nuc-infisical (`192.168.0.21`)

| Service | Notes |
|---------|-------|
| Infisical | Machine-consumed secrets (service API keys, inter-service tokens). Each VM fetches secrets at boot via `infisical export` |
| Vaultwarden | Human-consumed secrets (web UI admin passwords). One manual browser registration at bootstrap; persists on NFS forever |
| Litestream | Continuously streams the Vaultwarden SQLite WAL to Storinator NFS |

### nuc-deploy (`192.168.0.23`)

| Service | Notes |
|---------|-------|
| Terraform | Provisions NUC and Anton VMs. State stored in MinIO on Storinator |
| Ansible | Push-only config management for all VMs and physical nodes |

### nuc-haos (`192.168.0.22`)

| Service | Notes |
|---------|-------|
| Home Assistant OS | Home automation. Restored from vzdump backup on first boot — not managed via cloud-init or Ansible |

---

## Anton VMs

### anton-services (`192.168.0.31`)

| Service | Notes |
|---------|-------|
| Traefik | Reverse proxy. Two entrypoints: `web` (port 80, `*.home`) and `websecure` (port 443, `*.wsh`) |
| step-ca | Local CA. Issues wildcard `*.wsh` TLS certs; Traefik uses it as the ACME endpoint |
| Jellyfin | Media server. Quadro P2000 passthrough for hardware transcoding |
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

### anton-ollama (`192.168.0.30`)

| Service | Notes |
|---------|-------|
| Ollama | GPU inference server. RTX 3060 passthrough (hostpci pending — see TODOS.md) |
| Tailscale exit node | Backup exit node for the tailnet |

### anton-openclaw (`192.168.0.32`)

| Service | Notes |
|---------|-------|
| OpenClaw | Personal AI assistant gateway. Permanent on Anton |

### anton-debian (`192.168.0.33`)

| Service | Notes |
|---------|-------|
| Debian workstation | Personal development environment |
