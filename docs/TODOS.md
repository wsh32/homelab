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

