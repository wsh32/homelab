locals {
  node = "diglett"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms

  # Shared VM defaults -- keep in sync with modules/proxmox-vm/main.tf
  vm_defaults = {
    cpu_type  = "x86-64-v2-AES"
    bridge    = "vmbr0"
    nic_model = "virtio"
    os_type   = "l26"
    datastore = "local-lvm"
  }
}

# Download Ubuntu 24.04 (Noble) cloud image to Diglett once.
resource "proxmox_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "dns" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["diglett-dns"].vm_id
  name          = "diglett-dns"
  description   = "AdGuard Home DNS + Tailscale exit node (primary)"
  tags          = ["diglett", "infra", "dns"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 2
  memory_mb    = 2048
  disk_size_gb = 10
  swap_size_gb = 1

  ip_address         = "${local.vms["diglett-dns"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  extra_runcmd = [
    "tailscale set --advertise-exit-node",
    # /etc/headscale.env is read by both the headscale and cloudflare-ddns containers.
    # CF_API_TOKEN / DOMAINS / PROXIED: used by the cloudflare-ddns sidecar.
    "echo 'CF_API_TOKEN=${var.cloudflare_api_token}' > /etc/headscale.env",
    "echo 'DOMAINS=${local.headscale_hostname}' >> /etc/headscale.env",
    "echo 'PROXIED=false' >> /etc/headscale.env",
    "echo 'HEADSCALE_SERVER_URL=https://${local.headscale_hostname}' >> /etc/headscale.env",
    "echo 'HEADSCALE_TLS_LETSENCRYPT_HOSTNAME=${local.headscale_hostname}' >> /etc/headscale.env",
    "chmod 600 /etc/headscale.env",
  ]
}

module "infra" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["diglett-infra"].vm_id
  name          = "diglett-infra"
  description   = "Infra -- Traefik, step-ca, Infisical, Vaultwarden, Authentik"
  tags          = ["diglett", "infra"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 4
  memory_mb    = 12288
  disk_size_gb = 40
  swap_size_gb = 2

  ip_address         = "${local.vms["diglett-infra"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  extra_runcmd = []
}

# TODO: Manage HAOS VM in Terraform.
# HAOS image releases use .qcow2.xz compression which the bpg/proxmox provider
# does not support (only gz/lzo/zst/bz2). For now, create the VM manually:
#   1. SSH to diglett, download and decompress the image:
#      wget -O /tmp/haos.qcow2.xz https://github.com/home-assistant/operating-system/releases/download/17.3/haos_ova-17.3.qcow2.xz
#      xz -d /tmp/haos.qcow2.xz
#   2. Create VM via Proxmox UI (VM ID 202, 2 cores, 4GB RAM, import disk from /tmp/haos.qcow2)
#   3. Restore config from vzdump backup after first boot.
