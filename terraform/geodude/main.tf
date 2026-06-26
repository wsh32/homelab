locals {
  node = "geodude"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  loc  = local.net.locations.geodude
  vms  = local.loc.nodes[local.node].vms
  gw   = local.loc.gateway
  dns  = local.loc.dns
}

# Download Ubuntu 24.04 (Noble) cloud image to Geodude once.
resource "proxmox_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "dev" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["geodude-dev"].vm_id
  name          = "geodude-dev"
  description   = "Offsite development / test VM"
  tags          = ["geodude", "dev"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 4
  memory_mb    = 8192
  disk_size_gb = 40
  swap_size_gb = 2

  ip_address  = "${local.vms["geodude-dev"].ip}/${local.loc.subnet_prefix}"
  gateway     = local.gw
  dns_servers = [local.dns.primary, local.dns.fallback]

  ssh_public_key = var.ssh_public_key
  vm_password    = var.vm_password
  timezone       = var.timezone

  # Second NIC on vmbr1 so geodude's Tailscale subnet route covers this VM.
  # IP last octet mirrors the LAN IP (192.168.1.20 → 10.0.3.20).
  bridge_secondary    = "vmbr1"
  bridge_secondary_ip = "10.0.3.20/24"
}
