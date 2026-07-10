locals {
  node = "dratini"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  loc  = local.net.locations.bryant
  vms  = local.loc.nodes[local.node].vms
}

# Download Ubuntu 24.04 (Noble) cloud image to Dratini once.
# Re-applying after first download is a no-op (overwrite = false).
resource "proxmox_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "server" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["dratini-server"].vm_id
  name          = "dratini-server"
  description   = "Game server host -- Pelican panel + Wings (Minecraft, Palworld, etc.)"
  tags          = ["dratini", "services", "games"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 8
  memory_mb    = 65536
  disk_size_gb = 100
  swap_size_gb = 2
  datastore    = var.vm_datastore

  ip_address          = "${local.vms["dratini-server"].ip}/24"
  gateway             = local.loc.gateway
  dns_servers         = [local.loc.dns.primary, local.loc.dns.fallback]
  bridge_secondary    = "vmbr1"
  bridge_secondary_ip = "${local.vms["dratini-server"].bridge_ip}/24"
  ssh_public_key      = var.ssh_public_key
  vm_password         = var.vm_password
  timezone            = var.timezone
}

module "host" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["dratini-host"].vm_id
  name          = "dratini-host"
  description   = "GPU streaming host -- Wolf for Moonlight (dratini-gpu passthrough)"
  tags          = ["dratini", "services", "gpu"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 6
  memory_mb    = 16384
  disk_size_gb = 80
  swap_size_gb = 2
  datastore    = var.vm_datastore

  ip_address          = "${local.vms["dratini-host"].ip}/24"
  gateway             = local.loc.gateway
  dns_servers         = [local.loc.dns.primary, local.loc.dns.fallback]
  bridge_secondary    = "vmbr1"
  bridge_secondary_ip = "${local.vms["dratini-host"].bridge_ip}/24"
  ssh_public_key      = var.ssh_public_key
  vm_password         = var.vm_password
  timezone            = var.timezone

  machine          = "q35"
  hostpci_mappings = var.host_gpu_mappings
  # Fill in host_gpu_mappings in terraform.tfvars after creating the Proxmox
  # hardware mapping. See GPU passthrough section in docs/runbook.md.
  # Applying this to a running VM requires a full VM restart.
}
