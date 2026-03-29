# Repo Structure

A walkthrough of every file in this repo and what it does.

## Root

**`.gitignore`** — Excludes secrets and Terraform internals from git: `terraform.tfvars`, `.env`, `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl`, `*.pem`, `*.key`. Nothing sensitive can accidentally be committed.

**`README.md`** — Top-level overview: architecture diagram, repo structure, bootstrap steps, and the three-store secrets model (tfvars / Vaultwarden / Infisical).

**`CLAUDE.md`** — Instructions for Claude when working in this repo. Key conventions: which Terraform provider to use, what goes in each secrets store, VM ID/IP ranges, NFS mount paths, Traefik label format, headless-config rule.

---

## `docs/`

**`plan.md`** — The primary architecture document. Full network design, storage layout, VM resource budgets, the complete service list per VM, headless configuration strategy for every service, and the 13-step bootstrap sequence. If you're making a decision about architecture, it lives here.

**`TODOS.md`** — Deferred work items with full context: NFS export strategy, bootstrap runbook, GPU passthrough, backup DNS, Tailscale ACL segmentation, external uptime monitor, break-glass procedure, and headless bootstrap scripts. Each item has what/why/context/dependencies so they're actionable later.

**`hardware_inventory.md`** — Physical hardware reference: specs for Anton, NUC, Storinator, Gringotts, Orange Pi.

**`repo_structure.md`** — This file.

---

## `terraform/modules/proxmox-vm/`

The shared VM module. Every VM in the homelab is an instance of this module.

**`variables.tf`** — All inputs: `node_name`, `vm_id`, `name`, `cores`, `memory_mb`, `disk_size_gb`, `datastore`, `image_file_id` (the already-downloaded cloud image), `ip_address`, `gateway`, `dns_servers`, `ssh_public_key`, `tailscale_auth_key`, `user_data_extra`, `tags`.

**`main.tf`** — Two resources:
1. `proxmox_virtual_environment_file` — uploads a cloud-init YAML snippet to Proxmox local snippets storage. The snippet sets hostname, installs base packages (qemu-guest-agent, git, nfs-common, etc.), installs Tailscale, and joins the network. Accepts `user_data_extra` to inject extra `runcmd` steps per VM.
2. `proxmox_virtual_environment_vm` — creates the VM: CPU/RAM/disk from variables, clones root disk from the cloud image, attaches the cloud-init drive, sets static IP.

**`outputs.tf`** — Exposes `vm_id`, `name`, `ip_address`, and `ipv4_addresses` (live addresses from QEMU guest agent) so root modules can reference them.

---

## `terraform/anton/`

Root module for Anton. Owns everything on that Proxmox node.

**`versions.tf`** — Pins Terraform ≥1.9 and `bpg/proxmox ~0.73`. Configures the state backend — a local file path at `/mnt/terraform-state/anton/terraform.tfstate` (that path is on Storinator NFS, which you mount before running Terraform).

**`providers.tf`** — Configures the Proxmox provider with Anton's endpoint, API token, and SSH agent auth. SSH is required by the bpg provider to upload cloud-init snippets.

**`variables.tf`** — Four inputs: `proxmox_endpoint`, `proxmox_api_token`, `ssh_public_key`, `tailscale_auth_key`.

**`main.tf`** — Currently one download resource and one VM:
- `proxmox_virtual_environment_download_file.ubuntu_2404` — downloads the Ubuntu 24.04 LTS cloud image to Anton's local storage once. `overwrite = false` means re-applying is a no-op after the first download.
- `module.ubuntu` — the `anton-ubuntu` VM (VM ID 101, `192.168.0.13`, 6 cores, 16GB RAM, 60GB disk).

**`terraform.tfvars.example`** — Template showing the four values you need to fill in. Copy to `terraform.tfvars` (gitignored) and populate.

---

## `terraform/nuc/`

Same structure as `terraform/anton/`, but for the NUC node. VM ID range 200–299, IP range `192.168.0.20–29`.

Currently defines one VM: `nuc-infisical` (VM ID 201, `192.168.0.21`, 2 cores, 6GB RAM) with extra cloud-init to install Docker, since Infisical and Vaultwarden both run in containers.

---

## `ansible/`

Day-2 configuration management — runs after Terraform provisions VMs and cloud-init finishes.

**`ansible.cfg`** — Project-level Ansible config: points at the inventory, sets `ubuntu` as remote user, disables host key checking (VMs are freshly provisioned), enables SSH pipelining for speed.

**`inventory/hosts.yml`** — All hosts organized into groups: `physical` (Anton, NUC, Storinator, Orange Pi), `nuc_vms`, `anton_vms`, and a parent `vms` group that includes both. Playbooks can target `vms` to hit everything, or `nuc_vms` to hit just NUC VMs.

**`base.yml`** — Playbook that applies the `base` role to all VMs. The entry point for day-2 setup: `ansible-playbook ansible/base.yml`.

**`tailscale.yml`** — Bootstrap playbook for physical nodes only. Installs Tailscale from the official install script and joins the network. Runs before Terraform (physical nodes need to be on Tailscale before VMs are provisioned). Takes `TAILSCALE_AUTH_KEY` from env.

**`roles/base/tasks/main.yml`** — Applied to every Ubuntu VM. Installs fail2ban and UFW, enables the firewall (deny all inbound except SSH), disables password auth in sshd, sets the timezone, creates `/mnt/nas` (NFS mount point), and keeps Tailscale up to date.

**`roles/base/handlers/main.yml`** — Restart handlers for sshd, fail2ban, and tailscaled, triggered by the base tasks when config changes.

**`roles/docker/tasks/main.yml`** — Applied to VMs that run Docker Compose services. Adds the official Docker apt repo, installs Docker CE + compose plugin, configures log rotation (10MB max, 3 files), and adds the `ubuntu` user to the `docker` group.

**`roles/docker/handlers/main.yml`** — Restart handler for Docker daemon.

---

## What's not here yet

See `docs/TODOS.md` for full context on each item.

- `services/` — Docker Compose files for each VM's services
- `scripts/` — Headless init scripts (Infisical bootstrap, Jellyfin, Servarr, n8n, etc.)
- `cloud-init/` — Shared cloud-init templates
- `services/dns/adguard/AdGuardHome.yaml` — Pre-seeded AdGuard config
- Terraform resources for the remaining VMs (DNS, HAOS, Infisical, Ollama, OpenClaw, Services)
