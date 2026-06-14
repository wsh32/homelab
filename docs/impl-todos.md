# Implementation TODOs

Concrete implementation tasks, ordered by tier. High-level decisions live in `TODOS.md`.

---

## Bare minimum -- all VMs online, Terraform and Ansible proven out

Goal: every VM in `network.yml` is provisioned and passes `ansible-playbook ansible/base.yml`.

- [ ] **Verify bridge_port values** -- SSH to Machamp and Diglett, run `ip link show`, confirm the NIC bridged to `vmbr0` is `eno1` (or correct it in `network.yml`)
- [ ] **Add Cloudflare provider to Terraform** -- add `cloudflare/cloudflare` provider to `terraform/diglett/versions.tf`; add `cloudflare_api_token` to `variables.tf` and `terraform.tfvars.example`; add `cloudflare_tunnel` + `cloudflare_tunnel_config` + `cloudflare_record` resources for Headscale
- [ ] **Wire Cloudflare tunnel token into DNS VM cloud-init** -- pass the `cloudflare_tunnel` token output from Terraform into the DNS VM module as a variable; cloud-init writes it to the cloudflared env file
- [ ] **Fix Tailscale `--login-server` in cloud-init** -- add a `headscale_url` variable to `terraform/modules/proxmox-vm/`; thread it through all VM definitions; set to the Cloudflare Tunnel public URL
- [ ] **Write `ansible/bootstrap-deploy.yml`** -- playbook that clones the repo, installs Terraform and Ansible, and copies `terraform.tfvars` onto the deploy VM; run from operator laptop after `terraform apply -target=module.deploy`
- [ ] **Write `ansible/bootstrap-headscale.yml`** -- waits for Headscale healthy, generates a reusable pre-auth key via `docker exec headscale headscale preauthkeys create --reusable --expiration 365d`, patches `headscale_preauth_key` into `terraform.tfvars` on the deploy VM
- [ ] **Configure static IPs on physical nodes** -- run `ansible-playbook ansible/network.yml` for Machamp and Diglett; set static IPs on Alakazam and Ditto via TrueNAS UI
- [ ] **Bootstrap deploy VM** -- `terraform apply -target=module.deploy` from operator laptop; then `ansible-playbook ansible/bootstrap-deploy.yml`
- [ ] **Bootstrap DNS VM** -- `terraform apply -target=module.dns`; verify AdGuard, Headscale, and cloudflared are running; run `ansible-playbook ansible/bootstrap-headscale.yml`
- [ ] **Deploy all VMs** -- `terraform apply` from deploy VM; verify all VMs come online
- [ ] **Verify Ansible base** -- `ansible-playbook ansible/base.yml` runs clean against all VMs with no failures

---

## MVP -- core plumbing working: secrets, DNS, TLS, reverse proxy

Goal: `*.wsh` resolves and loads over HTTPS; `*.home` resolves and loads over HTTP; Infisical is seeded; all services running.

- [ ] **Write `ansible/bootstrap-infisical.yml`** -- waits for Infisical healthy; runs `infisical bootstrap`; creates a scoped machine identity per VM; writes `client_id`, `client_secret`, `workspace_id` to `/etc/infisical.env` (mode 0600) on each VM that needs secrets
- [ ] **Add Infisical export systemd unit to VM cloud-init** -- for Docker Compose VMs, add a systemd unit that runs `infisical export --format dotenv > /etc/homelab.env` (reading from `/etc/infisical.env`) before Docker Compose starts; Docker Compose stacks reference `env_file: /etc/homelab.env`
- [ ] **Write `ansible/site.yml`** -- top-level playbook that applies all service roles in dependency order; each role generates its own secrets, seeds them to Infisical, writes config, starts containers
- [ ] **Add secret seeding to each service Ansible role** -- for each service (Radarr, Sonarr, Prowlarr, CouchDB, n8n, Grafana, PhotoPrism, Calibre-Web, Jellyfin): generate API key/password, `infisical secrets set KEY=value`, write config, store admin password in Vaultwarden via `bw` CLI
- [ ] **Set AdGuard admin password hash** -- generate bcrypt hash, replace `CHANGEME_BCRYPT_HASH_HERE` in `services/diglett-dns/adguard/AdGuardHome.yaml`, commit
- [ ] **Initialize step-ca** -- Ansible role for step-ca: `step ca init`, export root CA cert; operator installs root CA on personal devices once
- [ ] **Set Headscale domain in config** -- replace placeholder `server_url` in `services/diglett-dns/headscale/config.yml` with the Cloudflare Tunnel public URL; commit
- [ ] **Automate Vaultwarden secret storage via `bw` CLI** -- after the one manual browser registration, write a script (or Ansible task in `ansible/roles/infra/`) that reads generated secrets from `/etc/homelab.env` on machamp-infra over SSH and uses `bw` CLI on the operator machine to create the following items in Vaultwarden:
  - `Vaultwarden Admin` (Login, no username, password = `VAULTWARDEN_ADMIN_TOKEN`, URL = `https://vault.home/admin`)
  - `Authentik` (Login, username = `akadmin`, password = `AUTHENTIK_BOOTSTRAP_PASSWORD`, URL = `https://auth.home`)
  - `Infisical` (Login, username = admin email, password = `INFISICAL_ADMIN_PASSWORD`, URL = `https://infisical.home`)
  - `AdGuard` (Login, username = `admin`, password = plaintext AdGuard password, URL = `https://adguard.home`)
  - `PostgreSQL` (Login, username = `postgres`, password = `POSTGRES_PASSWORD`, host = `192.168.0.32`)
  - `Headplane API Key` (Secure Note, contents of `/mnt/nas/docker/headplane/api.key` on diglett-dns)
  - Script should be idempotent: skip items that already exist (`bw list items --search <name>` before creating)
- [ ] **Test Vaultwarden account creation via `bw` CLI** -- attempt `bw config server http://vault.home && bw register`; document result; if unsupported, one manual browser registration is the accepted fallback
- [ ] **Add external API keys to Infisical** -- manually add `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, and any other external keys via Infisical UI
- [ ] **Upgrade PostgreSQL 16 → 17** -- PG16 is EOL Nov 2025; PG17 is current stable. Major version upgrades require a dump/restore: `docker exec postgres pg_dumpall -U postgres | gzip > /tmp/pgdump.sql.gz`, update image to `postgres:17-alpine`, wipe `/var/lib/postgres`, restart, restore. An NFS backup from `postgres-backup` can serve as the dump source. Do this during a maintenance window.

---

## Full capability -- all services running, GPU workloads, monitoring

Goal: everything in the plan is operational.

- [x] **GPU passthrough: extend proxmox-vm module** -- added `hostpci_devices` variable and dynamic `hostpci` block to `terraform/modules/proxmox-vm/`
- [ ] **GPU passthrough: Machamp hardware setup** -- on Machamp host, add `amd_iommu=on` to GRUB kernel params, load VFIO modules, bind both GPUs to VFIO before Proxmox claims them; document exact PCI addresses in `docs/hardware_inventory.md`
- [ ] **GPU passthrough: wire up Services VM** -- fill in `services_gpu_pci_ids` in `terraform/machamp/terraform.tfvars` once PCI address is confirmed (run `ssh root@machamp lspci | grep -i quadro`)
- [ ] **Deploy node_exporter** -- add `prom/node-exporter` to each service-running docker-compose stack (or as a standalone compose file on each VM); verify all targets appear green in Prometheus
- [ ] **Resolve Quartz approach** -- `ghcr.io/jackyzha0/quartz:v4` doesn't exist as a runnable web server image; Quartz is a static site generator. Options: (a) build the site in CI and serve the output with nginx, (b) run a Quartz build container on a cron and serve the output, (c) use a different publishing approach. Update `services/machamp-media/docker-compose.yml` once decided.
- [ ] **NUT/UPS integration** -- add Orange Pi to `network.yml` (type: other, assign IP in `.4–.19` range); write an Ansible role `roles/nut/` that installs and configures NUT server on Orange Pi and NUT clients on Machamp, Diglett, and Alakazam; add it to `ansible/physical.yml` and the relevant VM playbooks
- [ ] **Proxmox vzdump backup schedules** -- add `proxmox_virtual_environment_schedule` (or equivalent `bpg/proxmox` resource) Terraform resources for HAOS daily backup and all other VMs weekly backup, targeting the Alakazam `backups` NFS dataset
