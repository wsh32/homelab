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
| AdGuard Home | LAN DNS resolver. Pre-seeded config — no setup wizard. DNS rewrites: `*.wsh` → CNAME `machamp-infra.ts.home`, `*.home` → A `192.168.0.32` |
| Headscale | Self-hosted Tailscale coordination server. Pushes AdGuard's Tailscale IP as the DNS resolver for `.wsh` and `.home` to all tailnet members |
| cloudflared | Cloudflare Tunnel — exposes Headscale publicly without open ports or a static IP |
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
| Traefik | Reverse proxy. Two entrypoints: `web` (port 80, `*.home`) and `websecure` (port 443, `*.wsh`). Routes cross-VM backends via file provider (`traefik/dynamic/services-vm.yml`) |
| step-ca | Local CA. Issues wildcard `*.wsh` TLS certs; Traefik uses it as the ACME endpoint |
| Infisical | Machine-consumed secrets (service API keys, inter-service tokens). Each VM fetches secrets at boot via `infisical export` |
| Vaultwarden | Human-consumed secrets (web UI admin passwords). One manual browser registration at bootstrap; persists on NFS forever |
| Authentik | OIDC identity provider. SSO for Grafana, n8n, Headplane, and Headscale (configure OIDC clients post-deploy) |
| Litestream | Continuously streams the Vaultwarden SQLite WAL to Alakazam NFS |

### machamp-services (`192.168.0.30`)

| Service | Notes |
|---------|-------|
| Jellyfin | Media server. Quadro P2200 passthrough for hardware transcoding |
| Radarr | Movie library management |
| Sonarr | TV library management |
| Prowlarr | Indexer manager; linked to Radarr and Sonarr |
| qBittorrent | Torrent client; routes through Gluetun VPN |
| Gluetun | VPN gateway sidecar for qBittorrent |
| Bazarr | Subtitle management |
| Seerr | Media request and discovery frontend (formerly Jellyseerr) |
| Unpackerr | Post-download archive extraction for Servarr |

### machamp-dev (`192.168.0.31`)

| Service | Notes |
|---------|-------|
| development workstation | Personal development environment |
