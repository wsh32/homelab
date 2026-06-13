locals {
  node = "diglett"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms

  # Shared VM defaults — keep in sync with modules/proxmox-vm/main.tf
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

# Download HAOS qcow2 image for Home Assistant VM.
resource "proxmox_download_file" "haos" {
  node_name    = local.node
  content_type = "import"
  datastore_id = "local"

  url       = "https://github.com/home-assistant/operating-system/releases/download/17.3/haos_ova-17.3.qcow2.gz"
  file_name = "haos_ova-17.3.qcow2"

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
  description   = "Infra — Traefik, step-ca, Infisical, Vaultwarden, Authentik"
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

# HAOS uses a dedicated VM resource (not the proxmox-vm module) because it boots
# directly from the HAOS qcow2 image with no cloud-init. Configuration is restored
# from a Proxmox vzdump backup after first boot.
resource "proxmox_virtual_environment_vm" "haos" {
  node_name   = local.node
  vm_id       = local.vms["diglett-haos"].vm_id
  name        = "diglett-haos"
  description = "Home Assistant OS — restore config from vzdump backup after first boot"
  tags        = ["diglett", "haos"]

  on_boot = true

  cpu {
    cores = 2
    type  = local.vm_defaults.cpu_type
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = local.vm_defaults.datastore
    file_id      = proxmox_download_file.haos.id
    interface    = "virtio0"
    size         = 32
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = local.vm_defaults.bridge
    model  = local.vm_defaults.nic_model
  }

  operating_system {
    type = local.vm_defaults.os_type
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [disk[0].file_id]
  }
}
