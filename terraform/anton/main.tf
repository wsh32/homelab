locals {
  node = "anton"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms
}

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

module "ollama" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["anton-ollama"].vm_id
  name          = "anton-ollama"
  description   = "Ollama GPU inference (RTX 3060 passthrough) + Tailscale exit node (backup)"
  tags          = ["anton", "gpu", "ollama"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 4
  memory_mb    = 32768
  disk_size_gb = 60

  ip_address         = "${local.vms["anton-ollama"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker + NVIDIA container toolkit
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
    # Configure Tailscale backup exit node
    - tailscale set --advertise-exit-node
  EOF

  # TODO: GPU passthrough — add hostpci block after verifying RTX 3060 PCI address on Anton.
  # Run: ssh root@anton lspci | grep -i nvidia
}

module "openclaw" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["anton-openclaw"].vm_id
  name          = "anton-openclaw"
  description   = "OpenClaw — personal AI assistant gateway (permanent on Anton)"
  tags          = ["anton", "ai", "openclaw"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 2
  memory_mb    = 8192
  disk_size_gb = 20

  ip_address         = "${local.vms["anton-openclaw"].ip}/24"
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

module "debian" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["anton-debian"].vm_id
  name          = "anton-debian"
  description   = "Personal Debian development workstation"
  tags          = ["anton", "debian"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 6
  memory_mb    = 16384
  disk_size_gb = 60

  ip_address         = "${local.vms["anton-debian"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key
}

module "services" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["anton-services"].vm_id
  name          = "anton-services"
  description   = "Services VM — Traefik, Jellyfin, Servarr, Monitoring, etc. (Quadro P2000 passthrough)"
  tags          = ["anton", "gpu", "services"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 8
  memory_mb    = 32768
  disk_size_gb = 40

  ip_address         = "${local.vms["anton-services"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker + NVIDIA container toolkit
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
    # Mount NAS NFS volumes
    - mkdir -p /mnt/nas
    - echo "storinator:/mnt/pool/docker /mnt/nas/docker nfs soft,timeo=30,nfsvers=4 0 0" >> /etc/fstab
    - mount -a
  EOF

  # TODO: GPU passthrough — add hostpci block after verifying Quadro P2000 PCI address on Anton.
  # Run: ssh root@anton lspci | grep -i quadro
}
