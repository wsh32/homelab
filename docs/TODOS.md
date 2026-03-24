# TODOs

## NFS Export Strategy

**What:** Define which Storinator datasets get NFS-exported, to what clients, and with what permissions.

**Why:** MinIO on NUC mounts Storinator over NFS. Other VMs (Jellyfin, PhotoPrism, Servarr) will likely also need NFS mounts for media and persistent data. Without a consistent strategy, NFS config will be improvised per-service and become a mess.

**Pros:** Consistent, documented mount points. Easy to replicate on disaster recovery.

**Cons:** Requires thinking through access control (read-only vs read-write per dataset/client).

**Context:** Storinator has datasets: `backups`, `media`, `docker`, `terraform-state`, `photos`. Each needs a defined NFS export policy. Consider: should VMs mount datasets directly, or go through MinIO for object storage?

**Depends on:** Terraform module structure (below) — NFS mounts will be defined in VM cloud-init.

---

## Terraform Module Structure

**What:** Define the directory layout for Terraform code before writing any `.tf` files.

**Why:** The plan says "all VMs defined in Terraform" but doesn't specify structure. Deciding upfront prevents inconsistency as the repo grows.

**Pros:** Consistent, navigable codebase from day one.

**Cons:** Requires upfront design time before any VMs exist.

**Context:** Options to consider:
- `terraform/nodes/nuc/`, `terraform/nodes/anton/` — one directory per Proxmox node
- `terraform/services/jellyfin/`, `terraform/services/adguard/` — one directory per service
- `terraform/modules/vm/` shared module, called from per-node root modules

Recommended: shared `modules/vm` module + per-node root modules. Avoids duplication across nodes.

**Depends on:** Nothing — should be decided before any `.tf` files are written.

---

## Bootstrap Runbook

**What:** Write a step-by-step runbook with exact commands for the manual bootstrap phase.

**Why:** The plan defines 6 bootstrap steps at a high level. A runbook with exact commands makes it possible to rebuild the homelab from scratch in an hour rather than piecing it together from memory.

**Pros:** Fast disaster recovery. Onboarding yourself after a long break. Validates the bootstrap sequence actually works.

**Cons:** Takes time to write and maintain as the bootstrap process evolves.

**Context:** Bootstrap steps per plan:
1. Proxmox cluster join (Anton + NUC)
2. Ubuntu cloud-init template on each node
3. MinIO VM on NUC (with Storinator NFS mount)
4. Infisical Docker container on NUC infra VM
5. Tailscale on all physical nodes
6. Configure Terraform backend + Infisical provider

**Depends on:** NFS export strategy, Terraform module structure.

---

## Proxmox GPU Passthrough for Ollama

**What:** Document and implement IOMMU/VFIO configuration for passing the RTX 3060 through to the Ollama VM on Anton.

**Why:** GPU passthrough in Proxmox requires specific kernel parameters (`intel_iommu=on`, VFIO module loading) on the host, and correct PCIe device binding. Easy to misconfigure; results in either a broken VM or the GPU not being recognized by Ollama.

**Pros:** Ollama gets full GPU performance. RTX 3060 fully utilized for inference.

**Cons:** VFIO config ties the GPU exclusively to one VM — the GPU can't be shared with other VMs or the host.

**Context:** Anton has an i5-12600kf (supports VT-d) and RTX 3060. The Ollama VM needs the GPU passed through exclusively. After passthrough, the Proxmox host will have no display output from that GPU. Plan for this: Anton likely has no monitor attached anyway.

**Depends on:** Terraform module structure (GPU passthrough config goes in the Ollama VM definition).
