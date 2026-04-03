locals {
  node = "nuc"
  net  = yamldecode(file("${path.module}/../../network.yml"))
}

# Download Debian 12 (Bookworm) cloud image to NUC once.
resource "proxmox_virtual_environment_download_file" "debian_12" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name = "debian-12-genericcloud-amd64.qcow2"

  overwrite = false
}

module "infisical" {
  source = "../modules/proxmox-vm"

  node_name    = local.node
  vm_id        = local.net.vms["nuc-infisical"].vm_id
  name         = "nuc-infisical"
  description  = "Infisical (secrets manager) + Vaultwarden (password manager)"
  tags         = ["nuc", "infra", "infisical"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 2
  memory_mb    = 6144
  disk_size_gb = 20

  ip_address         = "${local.net.vms["nuc-infisical"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
  EOF
}
