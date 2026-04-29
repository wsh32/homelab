locals {
  node = "nuc"
  net  = yamldecode(file("${path.module}/../../network.yml"))
  vms  = local.net.nodes[local.node].vms
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

# Download HAOS qcow2 image for Home Assistant VM.
resource "proxmox_virtual_environment_download_file" "haos" {
  node_name    = local.node
  content_type = "import"
  datastore_id = "local"

  url       = "https://github.com/home-assistant/operating-system/releases/download/13.2/haos_ova-13.2.qcow2.gz"
  file_name = "haos_ova-13.2.qcow2"

  decompression_algorithm = "gz"
  overwrite               = false
}

module "dns" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["nuc-dns"].vm_id
  name          = "nuc-dns"
  description   = "AdGuard Home DNS + Tailscale exit node (primary)"
  tags          = ["nuc", "infra", "dns"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 2
  memory_mb    = 2048
  disk_size_gb = 10

  ip_address         = "${local.vms["nuc-dns"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Docker
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
    # Configure Tailscale exit node
    - tailscale set --advertise-exit-node
  EOF
}

module "infisical" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["nuc-infisical"].vm_id
  name          = "nuc-infisical"
  description   = "Infisical (secrets manager) + Vaultwarden (password manager)"
  tags          = ["nuc", "infra", "infisical"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 2
  memory_mb    = 6144
  disk_size_gb = 20

  ip_address         = "${local.vms["nuc-infisical"].ip}/24"
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

# HAOS uses a dedicated VM resource — no cloud-init, restored from vzdump backup.
resource "proxmox_virtual_environment_vm" "haos" {
  node_name   = local.node
  vm_id       = local.vms["nuc-haos"].vm_id
  name        = "nuc-haos"
  description = "Home Assistant OS — restore config from vzdump backup after first boot"
  tags        = ["nuc", "haos"]

  on_boot = true

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.haos.id
    interface    = "virtio0"
    size         = 32
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [disk[0].file_id]
  }
}

module "deploy" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["nuc-deploy"].vm_id
  name          = "nuc-deploy"
  description   = "Terraform + Ansible + internal webhook listener (Tailscale only)"
  tags          = ["nuc", "infra", "deploy"]
  image_file_id = proxmox_virtual_environment_download_file.debian_12.id

  cores        = 1
  memory_mb    = 1024
  disk_size_gb = 20

  ip_address         = "${local.vms["nuc-deploy"].ip}/24"
  gateway            = local.net.gateway
  dns_servers        = local.net.dns
  ssh_public_key     = var.ssh_public_key
  tailscale_auth_key = var.tailscale_auth_key

  user_data_extra = <<-EOF
    # Install Terraform
    - apt-get install -y gnupg software-properties-common
    - wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    - echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
    - apt-get update && apt-get install -y terraform
    # Install Ansible
    - apt-get install -y python3-pip
    - pip3 install ansible
    # Install Docker (for webhook container)
    - apt-get install -y docker.io docker-compose-plugin
    - systemctl enable --now docker
  EOF
}
