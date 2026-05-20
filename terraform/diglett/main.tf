locals {
  node = "diglett"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms
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

# Download HAOS qcow2 image for Home Assistant VM.
resource "proxmox_download_file" "haos" {
  node_name    = local.node
  content_type = "import"
  datastore_id = "local"

  url       = "https://github.com/home-assistant/operating-system/releases/download/13.2/haos_ova-13.2.qcow2.gz"
  file_name = "haos_ova-13.2.qcow2"

  decompression_algorithm = "gz"
  overwrite               = false
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
  tailscale_auth_key = var.tailscale_auth_key

  extra_runcmd = [
    "tailscale set --advertise-exit-node",
    "echo 'TUNNEL_TOKEN=${cloudflare_zero_trust_tunnel_cloudflared.headscale.tunnel_token}' > /etc/cloudflared.env",
    "echo 'HEADSCALE_SERVER_URL=https://${local.headscale_hostname}' >> /etc/cloudflared.env",
    "chmod 600 /etc/cloudflared.env",
  ]
}

module "infisical" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["diglett-infisical"].vm_id
  name          = "diglett-infisical"
  description   = "Infisical (secrets manager) + Vaultwarden (password manager)"
  tags          = ["diglett", "infra", "infisical"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 2
  memory_mb    = 6144
  disk_size_gb = 20
  swap_size_gb = 2

  ip_address         = "${local.vms["diglett-infisical"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  tailscale_auth_key = var.tailscale_auth_key

  extra_runcmd = []
}

# HAOS uses a dedicated VM resource — no cloud-init, restored from vzdump backup.
resource "proxmox_virtual_environment_vm" "haos" {
  node_name   = local.node
  vm_id       = local.vms["diglett-haos"].vm_id
  name        = "diglett-haos"
  description = "Home Assistant OS — restore config from vzdump backup after first boot"
  tags        = ["diglett", "haos"]

  on_boot = true

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.haos.id
    interface    = "virtio0"
    size         = 32
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [disk[0].file_id]
  }
}
