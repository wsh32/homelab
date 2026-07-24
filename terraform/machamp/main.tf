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
  bridge_secondary     = "vmbr1"
  bridge_secondary_ip  = "${local.vms["machamp-dev"].bridge_ip}/24"
  ssh_public_key       = var.ssh_public_key
  vm_password          = var.vm_password
  timezone             = var.timezone
}

module "ai" {
  source = "../modules/proxmox-vm"

  node_name     = local.node
  vm_id         = local.vms["machamp-ai"].vm_id
  name          = "machamp-ai"
  description   = "AI VM -- Ollama LLM host (RTX 6000 Ada passthrough)"
  tags          = ["machamp", "gpu", "ai"]
  image_file_id = proxmox_download_file.ubuntu_2404.id

  # 64GB RAM: Machamp has 128GB; machamp-media (32) + machamp-dev (16) + host
  # overhead (~4) leaves ~76GB. PCIe passthrough pins guest RAM (no ballooning),
  # so 96GB would not fit alongside the other VMs -- 64GB leaves headroom.
  cores     = 16
  memory_mb = 65536
  cpu_type  = "host"  # expose AVX2/AVX-512 for any CPU-offloaded model layers

  # Large root disk holds the Ollama model store on local NVMe (not NFS -- models
  # are re-pullable and NFS is too slow to page weights into VRAM). Point
  # ai_disk_datastore at an NVMe-backed datastore; the boot SSD is too small.
  disk_size_gb = 512
  datastore    = var.ai_disk_datastore

  ip_address           = "${local.vms["machamp-ai"].ip}/24"
  gateway              = local.loc.gateway
  dns_servers          = [local.loc.dns.primary, local.loc.dns.fallback]
  bridge_secondary     = "vmbr1"
  bridge_secondary_ip  = "${local.vms["machamp-ai"].bridge_ip}/24"
  ssh_public_key       = var.ssh_public_key
  vm_password          = var.vm_password
  timezone             = var.timezone

  machine          = "q35"
  bios             = "ovmf"  # UEFI -- SeaBIOS can't execute the Ada's UEFI-only VBIOS
  hostpci_mappings = var.ai_gpu_mappings
  # Fill in ai_gpu_mappings in terraform.tfvars after creating the Proxmox
  # hardware mapping. See GPU passthrough section in docs/runbook.md.
  # Applying this to a running VM requires a full VM restart.
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
  bridge_secondary     = "vmbr1"
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
