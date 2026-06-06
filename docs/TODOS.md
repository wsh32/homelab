# TODOs

## OIDC Client Configuration for Authentik

**What:** Wire up OIDC clients in Authentik for Headscale, Headplane, Grafana, and n8n. Authentik itself is already deployed on `machamp-infra`.

**Why:** headplane currently requires pasting a headscale API key at every login. OIDC gives a proper login flow and a single credential to manage. Headscale OIDC means new devices authenticate via Authentik instead of pre-auth keys. Grafana and n8n also benefit from unified SSO.

**Work:**
1. Headless Authentik bootstrap via Ansible: use Authentik's API to create OAuth2 providers and applications for each service (client ID + secret), write credentials to Infisical
2. **Headscale OIDC** — add `oidc:` block to `services/diglett-dns/headscale/config.yaml` pointing at `http://auth.home/application/o/headscale/`; store client secret in `/etc/headscale.env` on diglett-dns (alongside existing `HEADSCALE_SERVER_URL`); restore `autoApprovers` in `acls.hujson` using the Authentik user's email (e.g. `"wesoohoo@gmail.com"`) now that headscale auto-creates users from OIDC identity
3. Add `oidc:` block to `services/diglett-dns/headplane/config.yaml`; pull client secret from `/etc/headscale.env`
4. Add OIDC environment variables to Grafana and n8n in `services/machamp-services/docker-compose.yml`

**Headscale OIDC enrollment note:** when enrolling a device that is not yet on LAN or Tailscale (e.g. a phone from outside), the browser redirect to `auth.home` won't resolve. Mitigation: keep a reusable pre-auth key as a bootstrap fallback (`headscale preauthkeys create --reusable`), or expose Authentik publicly via Cloudflare Tunnel.

**Secret management:**
- Headscale / headplane / Grafana / n8n OIDC client secrets → Infisical, injected by Ansible

**Depends on:** `machamp-infra` VM deployed and Authentik bootstrapped, `machamp-services` VM deployed, Traefik + step-ca running.

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

## Tailscale Subnet Router + LAN Access Lockdown

**What:** Configure diglett-dns as a Tailscale subnet router so `.wsh` works when remote, and add IP allowlist middleware to restrict sensitive services from LAN guests.

**Why:** `.wsh` Traefik routers and DNS rewrites are already deployed (both resolve to `192.168.0.32`). The remaining work is the runtime Tailscale setup and per-service access hardening.

**Work:**
1. Register diglett-dns on the Headscale tailnet (install Tailscale client on the VM, generate a pre-auth key, join with `--login-server`)
2. Enable subnet routing on diglett-dns: `tailscale up --advertise-routes=192.168.0.0/24`
3. Approve the subnet route in Headscale: `headscale routes enable -r <route-id>` (or via Headplane)
4. Update `headscale/config.yaml` `nameservers.global` placeholder (`0.0.0.0`) with the actual diglett-dns Tailscale IP after it joins
5. Add Traefik IP allowlist middleware (source range `192.168.0.0/24`) for sensitive services that should be restricted to personal devices: `traefik.home`, `prometheus.home`, `couchdb.home`, `infisical.home`
6. Consider removing `.wsh` routers for Servarr (no remote access needed for Radarr/Sonarr/Prowlarr)

**Depends on:** diglett-dns VM deployed and running Headscale.

---

## UFW Firewall Hardening

**What:** Enable UFW on all VMs with a default-deny policy and per-role allowlists.

**Why:** Currently no host firewall is configured. All ports are open on the LAN. Tailscale provides network-level segmentation but no per-VM port filtering.

**Minimum policy per role:**
- All VMs: allow SSH (22)
- `services` VMs: allow Docker bridge traffic
- `diglett-dns`: allow DNS (53 TCP/UDP), AdGuard UI (3000 TCP) from LAN
- `machamp-services`: allow Traefik (80, 443) from LAN and Tailscale
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

## Break-glass Procedure

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

