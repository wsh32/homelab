# Implementation TODOs

Concrete implementation tasks, ordered by tier. High-level decisions live in `TODOS.md`.

---

## Bare minimum — all VMs online, Terraform and Ansible proven out

Goal: every VM in `network.yml` is provisioned and passes `ansible-playbook ansible/base.yml`.

- [ ] **Verify bridge_port values** — SSH to Machamp and Diglett, run `ip link show`, confirm the NIC bridged to `vmbr0` is `eno1` (or correct it in `network.yml`)
- [ ] **Add Cloudflare provider to Terraform** — add `cloudflare/cloudflare` provider to `terraform/diglett/versions.tf`; add `cloudflare_api_token` to `variables.tf` and `terraform.tfvars.example`; add `cloudflare_tunnel` + `cloudflare_tunnel_config` + `cloudflare_record` resources for Headscale
- [ ] **Switch Terraform to S3 backend** — update `terraform/diglett/versions.tf` and `terraform/machamp/versions.tf` to use an `s3` backend block pointed at MinIO on Alakazam (`http://192.168.0.4:9000`, bucket `terraform-state`); add `minio_access_key` / `minio_secret_key` to `variables.tf` and `terraform.tfvars.example`
- [ ] **Wire Cloudflare tunnel token into DNS VM cloud-init** — pass the `cloudflare_tunnel` token output from Terraform into the DNS VM module as a variable; cloud-init writes it to the cloudflared env file
- [ ] **Fix Tailscale `--login-server` in cloud-init** — add a `headscale_url` variable to `terraform/modules/proxmox-vm/`; thread it through all VM definitions; set to the Cloudflare Tunnel public URL
- [ ] **Write `ansible/bootstrap-deploy.yml`** — playbook that clones the repo, installs Terraform and Ansible, and copies `terraform.tfvars` onto the deploy VM; run from operator laptop after `terraform apply -target=module.deploy`
- [ ] **Write `ansible/bootstrap-headscale.yml`** — waits for Headscale healthy, generates a reusable pre-auth key via `docker exec headscale headscale preauthkeys create --reusable --expiration 365d`, patches `headscale_preauth_key` into `terraform.tfvars` on the deploy VM
- [ ] **Configure static IPs on physical nodes** — run `ansible-playbook ansible/network.yml` for Machamp and Diglett; set static IPs on Alakazam and Ditto via TrueNAS UI
- [ ] **Bootstrap deploy VM** — `terraform apply -target=module.deploy` from operator laptop; then `ansible-playbook ansible/bootstrap-deploy.yml`
- [ ] **Bootstrap DNS VM** — `terraform apply -target=module.dns`; verify AdGuard, Headscale, and cloudflared are running; run `ansible-playbook ansible/bootstrap-headscale.yml`
- [ ] **Deploy all VMs** — `terraform apply` from deploy VM; verify all VMs come online
- [ ] **Verify Ansible base** — `ansible-playbook ansible/base.yml` runs clean against all VMs with no failures

---

## MVP — core plumbing working: secrets, DNS, TLS, reverse proxy

Goal: `*.wsh` resolves and loads over HTTPS; `*.home` resolves and loads over HTTP; Infisical is seeded; all services running.

- [ ] **Write `ansible/bootstrap-infisical.yml`** — waits for Infisical healthy; runs `infisical bootstrap`; creates a scoped machine identity per VM; writes `client_id`, `client_secret`, `workspace_id` to `/etc/infisical.env` (mode 0600) on each VM that needs secrets
- [ ] **Add Infisical export systemd unit to VM cloud-init** — for Docker Compose VMs, add a systemd unit that runs `infisical export --format dotenv > /etc/homelab.env` (reading from `/etc/infisical.env`) before Docker Compose starts; Docker Compose stacks reference `env_file: /etc/homelab.env`
- [ ] **Write `ansible/site.yml`** — top-level playbook that applies all service roles in dependency order; each role generates its own secrets, seeds them to Infisical, writes config, starts containers
- [ ] **Add secret seeding to each service Ansible role** — for each service (Radarr, Sonarr, Prowlarr, CouchDB, n8n, Grafana, PhotoPrism, Calibre-Web, Jellyfin): generate API key/password, `infisical secrets set KEY=value`, write config, store admin password in Vaultwarden via `bw` CLI
- [ ] **Set AdGuard admin password hash** — generate bcrypt hash, replace `CHANGEME_BCRYPT_HASH_HERE` in `services/dns/adguard/AdGuardHome.yaml`, commit
- [ ] **Initialize step-ca** — Ansible role for step-ca: `step ca init`, export root CA cert; operator installs root CA on personal devices once
- [ ] **Set Headscale domain in config** — replace placeholder `server_url` in `services/dns/headscale/config.yml` with the Cloudflare Tunnel public URL; commit
- [ ] **Test Vaultwarden account creation via `bw` CLI** — attempt `bw config server http://vault.home && bw register`; document result; if unsupported, one manual browser registration is the accepted fallback
- [ ] **Add external API keys to Infisical** — manually add `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, and any other external keys via Infisical UI

---

## Full capability — all services running, GPU workloads, monitoring

Goal: everything in the plan is operational.

- [ ] **GPU passthrough: extend proxmox-vm module** — add an optional `pci_devices` variable (list of PCI address strings) to `terraform/modules/proxmox-vm/`; add a dynamic `hostpci` block to the VM resource; default to empty list so existing VMs are unaffected
- [ ] **GPU passthrough: Machamp hardware setup** — on Machamp host, add `amd_iommu=on` to GRUB kernel params, load VFIO modules, bind both GPUs to VFIO before Proxmox claims them; document exact PCI addresses in `docs/hardware_inventory.md`
- [ ] **GPU passthrough: wire up Ollama and Services VMs** — fill in the `pci_devices` argument for `module.ollama` (RTX 3060) and `module.services` (Quadro P2000) in `terraform/machamp/main.tf` once PCI addresses are confirmed
- [ ] **Deploy node_exporter** — add `prom/node-exporter` to each service-running docker-compose stack (or as a standalone compose file on each VM); verify all targets appear green in Prometheus
- [ ] **Resolve Quartz approach** — `ghcr.io/jackyzha0/quartz:v4` doesn't exist as a runnable web server image; Quartz is a static site generator. Options: (a) build the site in CI and serve the output with nginx, (b) run a Quartz build container on a cron and serve the output, (c) use a different publishing approach. Update `services/machamp/docker-compose.yml` once decided.
- [ ] **NUT/UPS integration** — write an Ansible role `roles/nut/` that installs and configures NUT server on Orange Pi and NUT clients on Machamp, Diglett, and Alakazam; add it to `ansible/physical.yml` and the relevant VM playbooks
- [ ] **Proxmox vzdump backup schedules** — add `proxmox_virtual_environment_schedule` (or equivalent `bpg/proxmox` resource) Terraform resources for HAOS daily backup and all other VMs weekly backup, targeting the Alakazam `backups` NFS dataset
