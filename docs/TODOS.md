# TODOs

## NFS Export Strategy

**What:** Define which Snorlax datasets get NFS-exported, to what
clients, and with what permissions.

**Why:** All VMs mount Snorlax over NFS for persistent data. Without a
consistent strategy, NFS config will be improvised per-service and become
a mess.

**Context:** Snorlax datasets: `backups`, `media`, `docker`,
`terraform-state`, `photos`, `lightroom`. Each needs a defined NFS export
policy (which VMs, read-only vs read-write). All mounts use
`soft,timeo=30` options.

**Depends on:** Terraform module structure - NFS mounts will be defined
in VM cloud-init.

---

## Proxmox GPU Passthrough for Ollama

**What:** Document and implement IOMMU/VFIO configuration for passing the RTX 3060 through to the Ollama VM on Machamp.

**Why:** GPU passthrough in Proxmox requires specific kernel parameters (`intel_iommu=on`, VFIO module loading) on the host, and correct PCIe device binding. Easy to misconfigure; results in either a broken VM or the GPU not being recognized by Ollama.

**Pros:** Ollama gets full GPU performance. RTX 3060 fully utilized for inference.

**Cons:** VFIO config ties the GPU exclusively to one VM — the GPU can't be shared with other VMs or the host.

**Context:** Machamp is a Lenovo P620 ThinkStation (Threadripper 3975WX, AMD platform) with two GPUs: RTX 3060 and Quadro P2000. Both can be passed through to separate VMs — RTX 3060 → Ollama VM (inference), Quadro P2000 → Services VM (Jellyfin transcoding). After passthrough, the Proxmox host will have no display output. Plan for this: Machamp likely has no monitor attached anyway. Note: AMD Threadripper uses AMD-Vi (IOMMU) rather than Intel VT-d — kernel param is `amd_iommu=on`.

**Depends on:** Terraform module structure (GPU passthrough config goes in the Ollama VM definition).

---

## Backup DNS VM

**What:** Deploy a secondary AdGuard Home instance on the Orange Pi.

**Why:** The primary DNS VM on the Diglett is a single point of failure.
Currently mitigated by 8.8.8.8 as fallback, but that bypasses ad-blocking
and breaks `.home` domain resolution.

**Depends on:** Nothing - can be done anytime after initial deployment.

---

## Tailscale ACL Segmentation

**What:** Add role-based ACL policy via the `tailscale_acl` Terraform
resource.

**Why:** All nodes currently communicate freely over Tailscale with no
segmentation. A compromised container has lateral movement to every node
including Ditto (offsite backup) and Proxmox management interfaces.

**Minimum policy:**
- Tag nodes by role (infra, compute, storage, backup)
- Restrict Ditto to replication traffic from Snorlax only
- Restrict Proxmox API ports to operator machine

**Depends on:** Terraform module structure.

---

## External Uptime Monitor

**What:** Deploy Uptime Kuma on the Orange Pi or use a cloud ping service
to monitor Snorlax and critical services externally.

**Why:** When Snorlax NFS hangs, the monitoring stack (Prometheus +
Grafana on Machamp) also goes down because it depends on Snorlax NFS.
An external monitor outside the NFS blast radius can detect and alert on
this.

**Depends on:** Nothing - can be done anytime.

---

## Break-glass Procedure

**What:** Document and maintain an offline copy of critical credentials
outside the homelab.

**Contents:**
- `terraform.tfvars` (Proxmox API token, Tailscale API key)
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

