# Pull secrets from Infisical
data "infisical_secrets" "anton" {
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/anton"
}

locals {
  tailscale_auth_key = data.infisical_secrets.anton.secrets["TAILSCALE_AUTH_KEY"].value
}

# Ollama VM — GPU inference, permanent on Anton
# NOTE: GPU passthrough (RTX 3060) requires IOMMU/VFIO config on Proxmox host.
# See TODOS.md — "Proxmox GPU Passthrough for Ollama"
module "ollama_vm" {
  source = "../modules/proxmox-vm"

  node      = "anton"
  vm_id     = 100
  name      = "anton-ollama"
  cores     = 4
  memory    = 32768 # 32GB
  disk_size = 100

  ssh_public_keys    = var.ssh_public_key
  tailscale_auth_key = local.tailscale_auth_key

  ip_address = "192.168.0.10/24"
  gateway    = "192.168.0.1"

  tags = ["anton", "ollama", "gpu"]
}

# Services VM — all temporary services (migrates to services node when built)
module "services_vm" {
  source = "../modules/proxmox-vm"

  node      = "anton"
  vm_id     = 101
  name      = "anton-services"
  cores     = 6
  memory    = 32768 # 32GB
  disk_size = 60

  ssh_public_keys    = var.ssh_public_key
  tailscale_auth_key = local.tailscale_auth_key

  ip_address = "192.168.0.11/24"
  gateway    = "192.168.0.1"

  tags = ["anton", "services", "docker"]

  user_data = file("${path.module}/../../cloud-init/docker-host.yaml")
}
