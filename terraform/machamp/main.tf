locals {
  node = "machamp"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms
}

# Download Ubuntu 24.04 (Noble) cloud image to Machamp once.
# Re-applying after first download is a no-op (overwrite = false).
resource "proxmox_virtual_environment_download_file" "ubuntu_2404" {
  node_name    = local.node
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  overwrite = false
}

module "ollama" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-ollama"].vm_id
  name          = "machamp-ollama"
  description   = "Ollama GPU inference (RTX 3060 passthrough) + Tailscale exit node (backup)"
  tags          = ["machamp", "gpu", "ollama"]
  image_file_id = proxmox_virtual_environment_download_file.ubuntu_2404.id

  cores        = 4
  memory_mb    = 32768
  disk_size_gb = 60

  ip_address         = "${local.vms["machamp-ollama"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker + NVIDIA container toolkit
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
    # Configure Tailscale backup exit node
    - tailscale set --advertise-exit-node
  EOF

  # TODO: GPU passthrough — add hostpci block after verifying RTX 3060 PCI address on Machamp.
  # Run: ssh root@machamp lspci | grep -i nvidia
}

module "openclaw" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-openclaw"].vm_id
  name          = "machamp-openclaw"
  description   = "OpenClaw — personal AI assistant gateway (permanent on Machamp)"
  tags          = ["machamp", "ai", "openclaw"]
  image_file_id = proxmox_virtual_environment_download_file.ubuntu_2404.id

  cores        = 2
  memory_mb    = 8192
  disk_size_gb = 20
  swap_size_gb = 2

  ip_address         = "${local.vms["machamp-openclaw"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  vm_password        = var.vm_password
  timezone           = var.timezone
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
  EOF
}

module "dev" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-dev"].vm_id
  name          = "machamp-dev"
  description   = "Personal development workstation"
  tags          = ["machamp", "dev"]
  image_file_id = proxmox_virtual_environment_download_file.ubuntu_2404.id

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
  image_file_id = proxmox_virtual_environment_download_file.ubuntu_2404.id

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

  user_data_extra = <<-EOF
    # Install Docker + NVIDIA container toolkit
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
    # Mount NAS NFS volumes
    - mkdir -p /mnt/nas
    - echo "alakazam:/mnt/pool/docker /mnt/nas/docker nfs soft,timeo=30,nfsvers=4 0 0" >> /etc/fstab
    - mount -a
  EOF

  # TODO: GPU passthrough — add hostpci block after verifying Quadro P2000 PCI address on Machamp.
  # Run: ssh root@machamp lspci | grep -i quadro
}
