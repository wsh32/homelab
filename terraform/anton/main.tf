locals {
  node = "anton"
}

# Anton VMs use IDs 100–199 and IPs 192.168.0.10–19.

# Download Ubuntu 24.04 LTS cloud image to Anton once.
# Re-applying after first download is a no-op (overwrite = false).
resource "proxmox_virtual_environment_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "ubuntu" {
  source = "../modules/proxmox-vm"

  node_name    = local.node
  vm_id        = 101
  name         = "anton-ubuntu"
  description  = "Personal Ubuntu development workstation"
  tags         = ["anton", "ubuntu"]
  image_file_id = proxmox_virtual_environment_download_file.ubuntu_2404.id

  cores        = 6
  memory_mb    = 16384
  disk_size_gb = 60

  ip_address         = "192.168.0.13/24"
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key
}
