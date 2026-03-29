locals {
  node = "anton"
}

# Anton VMs use IDs 100–199 and IPs 192.168.0.10–19.

# Download Debian 12 (Bookworm) cloud image to Anton once.
# Re-applying after first download is a no-op (overwrite = false).
resource "proxmox_virtual_environment_download_file" "debian_12" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name = "debian-12-genericcloud-amd64.qcow2"

  overwrite = false
}

module "debian" {
  source = "../modules/proxmox-vm"

  node_name    = local.node
  vm_id        = 101
  name         = "anton-debian"
  description  = "Personal Debian development workstation"
  tags         = ["anton", "debian"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 6
  memory_mb    = 16384
  disk_size_gb = 60

  ip_address         = "192.168.0.13/24"
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key
}
