locals {
  node = "nuc"
}

# NUC VMs use IDs 200–299 and IPs 192.168.0.20–29.

# Download Ubuntu 24.04 LTS cloud image to NUC once.
resource "proxmox_virtual_environment_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "infisical" {
  source = "../modules/proxmox-vm"

  node_name    = local.node
  vm_id        = 201
  name         = "nuc-infisical"
  description  = "Infisical (secrets manager) + Vaultwarden (password manager)"
  tags         = ["nuc", "infra", "infisical"]
  image_file_id = proxmox_virtual_environment_download_file.ubuntu_2404.id

  cores        = 2
  memory_mb    = 6144
  disk_size_gb = 20

  ip_address         = "192.168.0.21/24"
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
  EOF
}
