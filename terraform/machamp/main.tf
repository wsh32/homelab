locals {
  node = "machamp"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  loc  = local.net.locations.bryant
  vms  = local.loc.nodes[local.node].vms
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
  swap_size_gb = 2

  ip_address           = "${local.vms["machamp-dev"].ip}/24"
  gateway              = local.loc.gateway
  dns_servers          = [local.loc.dns.primary, local.loc.dns.fallback]
  bridge_secondary_ip  = "${local.vms["machamp-dev"].bridge_ip}/24"
  ssh_public_key       = var.ssh_public_key
  vm_password          = var.vm_password
  timezone             = var.timezone
}

module "services" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-media"].vm_id
  name          = "machamp-media"
  description   = "Media VM -- Jellyfin, Servarr stack, qBittorrent (Quadro P2200 passthrough)"
  tags          = ["machamp", "gpu", "media"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  cores        = 8
  memory_mb    = 32768
  disk_size_gb = 40

  ip_address           = "${local.vms["machamp-media"].ip}/24"
  gateway              = local.loc.gateway
  dns_servers          = [local.loc.dns.primary, local.loc.dns.fallback]
  bridge_secondary_ip  = "${local.vms["machamp-media"].bridge_ip}/24"
  ssh_public_key       = var.ssh_public_key
  vm_password          = var.vm_password
  timezone             = var.timezone
  extra_runcmd = []

  machine          = "q35"
  hostpci_mappings = var.services_gpu_mappings
  # Fill in services_gpu_mappings in terraform.tfvars after creating the Proxmox
  # hardware mapping. See GPU passthrough section in docs/runbook.md.
  # Applying this to a running VM requires a full VM restart.
}
