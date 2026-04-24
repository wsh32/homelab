# Implementation TODOs

Concrete implementation tasks, ordered by tier. High-level decisions live in `TODOS.md`.

---

## Bare minimum — all VMs online, Terraform and Ansible proven out

Goal: every VM in `network.yml` is provisioned, has a Tailscale IP, and passes `ansible-playbook base.yml`.

- [ ] **Verify bridge_port values** — SSH to Anton and NUC, run `ip link show`, confirm the NIC bridged to `vmbr0` is `eno1` (or correct it in `network.yml`)
- [ ] **Fix Tailscale `--login-server` in cloud-init** — `terraform/modules/proxmox-vm/main.tf` runs `tailscale up` with no `--login-server`. Add a `headscale_url` variable to the module and thread it through all VM definitions in `terraform/nuc/main.tf` and `terraform/anton/main.tf`
- [ ] **Provision VPS** — `cd terraform/vps && terraform apply`; note the public IP; back up `terraform.tfstate` in Vaultwarden
- [ ] **Bootstrap Headscale on VPS** — `ansible-playbook ansible/vps.yml -i <vps-ip>,` (one-time push to fresh droplet); verify `docker ps` shows headscale running
- [ ] **Generate Headscale pre-auth key** — `docker exec headscale headscale preauthkeys create --reusable --expiration 90d`; save the key
- [ ] **Configure static IPs on physical nodes** — run `ansible-playbook ansible/network.yml` for Anton and NUC; set static IPs on Storinator and Gringotts via TrueNAS UI
- [ ] **Install Tailscale on physical nodes** — `TAILSCALE_AUTH_KEY=<key> ansible-playbook ansible/tailscale.yml`; verify all physical nodes appear in `headscale nodes list`
- [ ] **Bootstrap deploy VM** — chicken-and-egg: run `terraform apply -target=module.deploy` from operator laptop; SSH in, clone repo, write `terraform.tfvars` for both `nuc/` and `anton/`
- [ ] **Deploy all VMs** — from deploy VM: `./scripts/deploy.sh both`; verify all VMs come online and appear in `headscale nodes list`
- [ ] **Verify Ansible base** — `ansible-playbook ansible/base.yml` runs clean against all VMs with no failures

---

## MVP — core plumbing working: secrets, DNS, TLS, reverse proxy, deploy automation

Goal: `*.wsh` resolves and loads over HTTPS; `*.home` resolves and loads over HTTP; Infisical is seeded; pushing to `main` triggers an automated deploy.

- [ ] **Switch Terraform to S3 backend** — update `terraform/nuc/versions.tf` and `terraform/anton/versions.tf` to use an `s3` backend block pointed at MinIO on Storinator (`http://storinator:9000`, bucket `terraform-state`); add `minio_access_key` / `minio_secret_key` to `variables.tf` and `terraform.tfvars.example` for both workspaces
- [ ] **Add Infisical export to VM boot** — for Docker Compose VMs (`nuc-infisical`, `nuc-deploy`, `anton-services`, `anton-openclaw`), add a systemd unit or cloud-init `runcmd` that installs the Infisical CLI and runs `infisical export --format dotenv > /etc/homelab.env` before Docker Compose starts; Docker Compose stacks should reference `env_file: /etc/homelab.env`
- [ ] **Bootstrap Infisical** — wait for `nuc-infisical` services to be healthy, then run `./scripts/infisical-bootstrap.sh`; add output credentials to `terraform.tfvars` on deploy VM; re-run `deploy.sh` to pick up new vars
- [ ] **Seed Infisical** — add all machine secrets via Infisical UI: servarr API keys, CouchDB credentials, PhotoPrism admin password, n8n encryption key, Grafana admin password, `WEBHOOK_SECRET`, any developer API keys
- [ ] **Create Vaultwarden account** — open `https://vault.home` (or `http://192.168.0.21:<port>`) in a browser; create account; store master password somewhere safe; signups lock automatically after first account
- [ ] **Set AdGuard admin password hash** — generate a bcrypt hash (`htpasswd -bnBC 10 "" <password> | tr -d ':\n'`), replace `CHANGEME_BCRYPT_HASH_HERE` in `services/dns/adguard/AdGuardHome.yaml`, commit and push
- [ ] **Initialize step-ca** — on `anton-services`, `docker exec step-ca step ca init ...`; copy root CA cert to operator laptop and trust it; repeat trust step on all personal devices
- [ ] **Fix Headscale `server_url`** — replace placeholder in `services/vps/headscale/config.yml` with the VPS public IP; commit and push (triggers vps.yml via webhook or manual run)
- [ ] **Set Headscale DNS nameserver IP** — after DNS VM is on Tailscale, look up its Tailscale IP (`headscale nodes list`); replace `100.64.0.2` in `services/vps/headscale/config.yml`; restart Headscale; verify `dig jellyfin.wsh` from a tailnet member resolves
- [ ] **Fix VPS IP in Ansible inventory** — replace `ansible_host: "{{ vps_ip }}"` in `ansible/inventory/hosts.yml` with the actual static VPS public IP; this unblocks `webhook-deploy.sh` running `ansible-playbook vps.yml`
- [ ] **Configure GitHub webhook** — in repo Settings → Webhooks: payload URL `http://<vps-ip>:9000/hooks/deploy`, secret = `WEBHOOK_SECRET` from Infisical, push events only
- [ ] **End-to-end webhook test** — push a small change to `main`; verify the VPS webhook fires, forwards to deploy VM, deploy VM runs `webhook-deploy.sh` without errors; check `/var/log/homelab-deploy.log`

---

## Full capability — all services running, GPU workloads, monitoring

Goal: everything in the plan is operational.

- [ ] **Fix servarr config.xml templating** — the XML files contain literal `${RADARR_API_KEY}` etc. which won't be substituted when mounted read-only. Options: (a) run `envsubst` in a cloud-init step to write final XML files before containers start, or (b) generate the files via Terraform `local_file` resources templated from `terraform.tfvars`. Pick one and implement it.
- [ ] **GPU passthrough: extend proxmox-vm module** — add an optional `pci_devices` variable (list of PCI address strings) to `terraform/modules/proxmox-vm/`; add a dynamic `hostpci` block to the VM resource; default to empty list so existing VMs are unaffected
- [ ] **GPU passthrough: Anton hardware setup** — on Anton host, add `amd_iommu=on` to GRUB kernel params, load VFIO modules, bind both GPUs to VFIO before Proxmox claims them; document exact PCI addresses in `docs/hardware_inventory.md`
- [ ] **GPU passthrough: wire up Ollama and Services VMs** — fill in the `pci_devices` argument for `module.ollama` (RTX 3060) and `module.services` (Quadro P2000) in `terraform/anton/main.tf` once PCI addresses are confirmed
- [ ] **Run headless init scripts** — after all services are up: `jellyfin-init.sh`, `servarr-init.sh`, `calibre-init.sh`, `n8n-init.sh`; store each service admin password in Vaultwarden immediately after
- [ ] **Deploy node_exporter** — add `prom/node-exporter` to each service-running docker-compose stack (or as a standalone compose file on each VM), then verify all targets appear green in Prometheus
- [ ] **Resolve Quartz approach** — `ghcr.io/jackyzha0/quartz:v4` doesn't exist as a runnable web server image; Quartz is a static site generator. Options: (a) build the site in CI and serve the output with nginx, (b) run a Quartz build container on a cron and serve the output, (c) use a different publishing approach. Update `services/anton/docker-compose.yml` once decided.
- [ ] **NUT/UPS integration** — write an Ansible role `roles/nut/` that installs and configures NUT server on Orange Pi and NUT clients on Anton, NUC, and Storinator; add it to `ansible/physical.yml` and the relevant VM playbooks
- [ ] **Proxmox vzdump backup schedules** — add `proxmox_virtual_environment_schedule` (or equivalent `bpg/proxmox` resource) Terraform resources for HAOS daily backup and all other VMs weekly backup, targeting the Storinator `backups` NFS dataset
