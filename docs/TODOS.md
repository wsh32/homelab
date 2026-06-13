# TODOs

## HAOS VM in Terraform

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

## Internal Bridge Network Isolation (vmbr1)

**What:** Create a Proxmox internal bridge (`vmbr1`) on machamp and attach machamp-infra and machamp-media to it, so Traefik can reach service backends without those ports being exposed on the LAN.

**Why:** Service ports (Jellyfin :8096, Radarr :7878, Sonarr :8989, etc.) currently bind on all interfaces (`0.0.0.0`), meaning any LAN device can hit them directly and bypass Traefik forwardAuth / Authentik. The internal bridge physically isolates that traffic to VM-to-VM only.

**Work:**
1. **Proxmox host** — add `vmbr1` internal bridge (no `bridge-ports`) to `/etc/network/interfaces` on machamp via `blockinfile` in `ansible/roles/proxmox/tasks/main.yml`. Gate on `internal_bridge` being defined for the node in `network.yml`.
2. **`network.yml`** — add `internal_bridge: vmbr1` to the machamp node; add `internal_ip` fields: machamp-infra `10.0.0.1`, machamp-media `10.0.0.2`.
3. **Terraform module** (`terraform/modules/proxmox-vm/`) — add optional `internal_ip` variable; when set, add a second `network_device { bridge = "vmbr1" }` and a second `ip_config` block in `initialization` (no gateway — host-only network).
4. **`terraform/machamp/main.tf`** — pass `internal_ip` from `network.yml` to the infra and services modules.
5. **`services/machamp-media/docker-compose.yml`** — change all port bindings from `PORT:PORT` to `10.0.0.2:PORT:PORT`.
6. **`services/machamp-infra/traefik/dynamic/services-vm.yml`** — update all backend URLs from `192.168.0.30` to `10.0.0.2`.

**Notes:**
- Cloud-init (`bpg/proxmox`) supports multiple `ip_config` blocks — second block maps to second NIC. No separate Ansible netplan task needed.
- machamp-media keeps its LAN IP (`192.168.0.30`) on `eth0` for SSH and NFS; only service ports move to `eth1` (`10.0.0.2`).
- Traefik on machamp-infra gets `10.0.0.1` on `eth1`; it already forwards traffic to the internal IPs.
- This is a **VM-recreation event** for machamp-infra and machamp-media (new NIC requires `terraform apply`).

**Depends on:** All services deployed and working on current topology (avoids debugging routing + services simultaneously).

---

## OIDC Client Configuration for Authentik

**What:** Wire up OIDC clients in Authentik for Headscale, Headplane, Grafana, and n8n. Authentik itself is already deployed on `machamp-infra`.

**Why:** headplane currently requires pasting a headscale API key at every login. OIDC gives a proper login flow and a single credential to manage. Headscale OIDC means new devices authenticate via Authentik instead of pre-auth keys. Grafana and n8n also benefit from unified SSO.

**Work:**
1. Headless Authentik bootstrap via Ansible: use Authentik's API to create OAuth2 providers and applications for each service (client ID + secret), write credentials to Infisical
2. **Headscale OIDC** — add `oidc:` block to `services/diglett-dns/headscale/config.yaml` pointing at `http://auth.home/application/o/headscale/`; store client secret in `/etc/headscale.env` on diglett-dns (alongside existing `HEADSCALE_SERVER_URL`); restore `autoApprovers` in `acls.hujson` using the Authentik user's email (e.g. `"wesoohoo@gmail.com"`) now that headscale auto-creates users from OIDC identity
3. Add `oidc:` block to `services/diglett-dns/headplane/config.yaml`; pull client secret from `/etc/headscale.env`
4. Add OIDC environment variables to Grafana and n8n in `services/machamp-media/docker-compose.yml`

**Headscale OIDC enrollment note:** when enrolling a device that is not yet on LAN or Tailscale (e.g. a phone from outside), the browser redirect to `auth.home` won't resolve. Mitigation: keep a reusable pre-auth key as a bootstrap fallback (`headscale preauthkeys create --reusable`), or expose Authentik publicly via Cloudflare Tunnel.

**Secret management:**
- Headscale / headplane / Grafana / n8n OIDC client secrets → Infisical, injected by Ansible

**Depends on:** `machamp-infra` VM deployed and Authentik bootstrapped, `machamp-media` VM deployed, Traefik + step-ca running.

---

## Authentik User Groups and Access Control

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
1. Add Authentik group bootstrap tasks to `ansible/roles/infra/tasks/main.yml`:
   - `POST /api/v3/core/groups/` to create `executives` and `grunts` (idempotent — skip if exists)
   - `POST /api/v3/policies/binding/` to bind each group to its allowed applications
2. Update `services/diglett-dns/headscale/acls.hujson` with group-based ACL rules using Authentik email claims as Headscale user identifiers
3. Document in `docs/plan.md`: to add a new user, create them in Authentik UI and add to the appropriate group — no code changes needed

**Notes:**
- Users are created manually in Authentik UI; only group definitions and application bindings live in code
- Headscale identifies users by email (via `sub_mode: user_email`); ACL rules reference `<email>@<domain>` or wildcard per group
- Group → Headscale ACL mapping requires that the Authentik group name is surfaced as a claim; alternatively, tag headscale nodes by enrollment group using headscale's user tagging

**Depends on:** Authentik OIDC fully working (Headscale enrollment confirmed).

---

## NFS Export Strategy

**What:** Define which Alakazam datasets get NFS-exported, to what
clients, and with what permissions.

**Why:** All VMs mount Alakazam over NFS for persistent data. Without a
consistent strategy, NFS config will be improvised per-service and become
a mess.

**Context:** Alakazam datasets: `backups`, `media`, `docker`,
`apps/terraform`, `photos`, `lightroom`. Each needs a defined NFS export
policy (which VMs, read-only vs read-write). All mounts use
`soft,timeo=30` options.

**Depends on:** Terraform module structure - NFS mounts will be defined
in VM cloud-init.

---

## Backup DNS VM

**What:** Deploy a secondary AdGuard Home instance as a backup DNS VM.

**Why:** The primary DNS VM on Diglett is a single point of failure.
Currently mitigated by 8.8.8.8 as fallback, but that bypasses ad-blocking
and breaks `.home` domain resolution.

**Depends on:** Nothing - can be done anytime after initial deployment.

---

## Tailscale `.wsh` Routing + LAN Access Lockdown

**What:** Re-add `.wsh` Traefik routers once Tailscale is fully up, and add IP allowlist middleware to restrict sensitive services on the LAN.

**Why:** All services are currently exposed on `.home` (LAN, no auth) for simplicity during bring-up. Tailscale routing and per-service IP allowlists are the next layer.

**Work:**
1. Wire up Tailscale (diglett-dns joining headscale, subnet router, DNS)
2. Restore `*.wsh` AdGuard rewrite to `machamp-infra.ts.home` and add `.wsh` routers in `services-vm.yml` and docker-compose labels for each service
3. Add Traefik IP allowlist middleware (source range `192.168.0.0/24`) for sensitive services that should never be publicly reachable even over Tailscale: `traefik.home`, `prometheus.home`, `couchdb.home`, `infisical.home`
4. Consider moving Servarr (.home only, no .wsh) since they don't need remote access

**Depends on:** Tailscale fully operational.

---

## UFW Firewall Hardening

**What:** Enable UFW on all VMs with a default-deny policy and per-role allowlists.

**Why:** Currently no host firewall is configured. All ports are open on the LAN. Tailscale provides network-level segmentation but no per-VM port filtering.

**Minimum policy per role:**
- All VMs: allow SSH (22)
- `services` VMs: allow Docker bridge traffic
- `diglett-dns`: allow DNS (53 TCP/UDP), AdGuard UI (3000 TCP) from LAN
- `machamp-media`: allow Traefik (80, 443) from LAN and Tailscale
- `machamp-infra`: allow Infisical (8080), Vaultwarden (80), and Authentik (9000) from LAN/Tailscale

**Note:** Add UFW tasks back to `ansible/roles/base/tasks/main.yml` and per-role allowlists to each service role. The base role previously had UFW enabled — removed to unblock initial bring-up.

**Depends on:** All services deployed and ports confirmed.

---

## Tailscale ACL Segmentation

**What:** Add role-based ACL policy via the `tailscale_acl` Terraform
resource.

**Why:** All nodes currently communicate freely over Tailscale with no
segmentation. A compromised container has lateral movement to every node
including Ditto (offsite backup) and Proxmox management interfaces.

**Minimum policy:**
- Tag nodes by role (infra, compute, storage, backup)
- Restrict Ditto to replication traffic from Alakazam only
- Restrict Proxmox API ports to operator machine

**Depends on:** Terraform module structure.

---

## External Uptime Monitor

**What:** Deploy Uptime Kuma on the Orange Pi or use a cloud ping service
to monitor Alakazam and critical services externally.

**Why:** When Alakazam NFS hangs, the monitoring stack (Prometheus +
Grafana on Machamp) also goes down because it depends on Alakazam NFS.
An external monitor outside the NFS blast radius can detect and alert on
this.

**Depends on:** Nothing - can be done anytime.

---

## Ansible Multi-OS Support

**What:** Handle OS differences in Ansible roles, starting with the SSH service name.

**Why:** Roles currently hardcode Ubuntu conventions. If Arch Linux VMs are ever added, at minimum the SSH service name differs (`ssh` on Ubuntu/Debian, `sshd` on Arch and most other distros). Other divergences likely exist (package manager, service manager, paths).

**Minimum change:** Use `ansible_facts['os_family']` to set the SSH service name, e.g. `ssh` for Debian family, `sshd` for Arch/RedHat.

**Depends on:** Actually adding a non-Ubuntu VM.

---

## Radarr/Sonarr Quality Profiles

**What:** Configure quality profiles via the arr API in `arr-init.yml` instead of manually through the UI.

**Desired settings:**
- **Movies (Radarr):** cutoff WEB-2160p, allow up to 4K WEB/Bluray, exclude Remux, max size ~50 GB for 4K / ~15 GB for 1080p
- **TV (Sonarr):** cutoff WEB-1080p, allow up to 1080p WEB/Bluray, exclude Remux, max size ~4 GB per episode

**Work:**
1. Fetch the default quality profile from Radarr/Sonarr to get quality IDs (`GET /api/v3/qualityprofile/1`)
2. Add a `PUT /api/v3/qualityprofile/{{ id }}` task in `arr-init.yml` with the desired `items` (allowed/disallowed) and `cutoff`
3. Drive size limits via `minSize`/`maxSize` on each quality item

**Notes:**
- Quality IDs are stable per Radarr version but should be fetched dynamically to be safe
- Remux IDs to disable: Remux-1080p (id varies), Remux-2160p

---



**What:** Document and maintain an offline copy of critical credentials
outside the homelab.

**Contents:**
- `terraform.tfvars` (Proxmox API token, Headscale pre-auth key)
- Infisical secrets export (all service runtime secrets)
- Proxmox root credentials
- `pvecm expected 1` quorum recovery command

**Why:** If the Diglett dies, running containers on Machamp survive but new
deploys are blocked until Infisical returns. An offline export allows
recovery without waiting for Diglett hardware replacement.

**Storage:** encrypted file in a password manager on phone, or USB drive.

**Depends on:** Initial deployment (secrets must exist before they can
be exported).

---

