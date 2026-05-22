# TODOs

## OIDC with Authentik

**What:** Deploy Authentik on `machamp-services` as the homelab OIDC identity provider, then wire headplane (and future services) to use it for SSO.

**Why:** headplane currently requires pasting a headscale API key at every login. OIDC gives a proper login flow and a single credential to manage. Authentik is the standard homelab choice — widely used, well documented, large library of pre-built integrations.

**Work:**
1. Add `authentik-server`, `authentik-worker`, `postgres`, and `redis` to `services/machamp/docker-compose.yml`; mount persistent data to `/mnt/nas/docker/authentik`
2. Add Traefik labels for `authentik.wsh` and `authentik.home`
3. Headless bootstrap via Ansible: use Authentik's API to create the headplane OAuth2 provider and application (client ID + secret), write credentials to Infisical
4. Add `oidc:` block to `services/dns/headplane/config.yaml`; pull client secret from Infisical at deploy time
5. Optional: configure headscale itself to use Authentik OIDC for node registration

**Secret management:**
- Authentik secret key and postgres password → Infisical
- headplane OIDC client secret → Infisical, injected into headplane config by Ansible

**Depends on:** `machamp-services` VM deployed, Traefik + step-ca running.

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
- `diglett-infra`: allow Infisical (8080) and Vaultwarden (8083) from LAN/Tailscale

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

