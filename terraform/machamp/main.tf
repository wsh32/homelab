locals {
  node = "machamp"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms
}

# Download Ubuntu 24.04 (Noble) cloud image to Machamp once.
# Re-applying after first download is a no-op (overwrite = false).
resource "proxmox_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "infra" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-infra"].vm_id
  name          = "machamp-infra"
  description   = "Infisical + Vaultwarden + Authentik — secrets and identity services"
  tags          = ["machamp", "infra"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 4
  memory_mb    = 12288
  disk_size_gb = 40
  swap_size_gb = 2
  cpu_type     = "host"   # MongoDB 7 requires AVX; host passthrough exposes it

  ip_address         = "${local.vms["machamp-infra"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  tailscale_auth_key = var.tailscale_auth_key

  extra_runcmd = []
}

module "dev" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-dev"].vm_id
  name          = "machamp-dev"
  description   = "Personal development workstation"
  tags          = ["machamp", "dev"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 6
  memory_mb    = 16384
  disk_size_gb = 60

  ip_address         = "${local.vms["machamp-dev"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  tailscale_auth_key = var.tailscale_auth_key
}

module "services" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-services"].vm_id
  name          = "machamp-services"
  description   = "Services VM — Traefik, Jellyfin, Servarr, Monitoring, etc. (Quadro P2000 passthrough)"
  tags          = ["machamp", "gpu", "services"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 8
  memory_mb    = 32768
  disk_size_gb = 40

  ip_address         = "${local.vms["machamp-services"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  tailscale_auth_key = var.tailscale_auth_key

  extra_runcmd = []

  # TODO: GPU passthrough — add hostpci block after verifying Quadro P2000 PCI address on Machamp.
  # Run: ssh root@machamp lspci | grep -i quadro
}
