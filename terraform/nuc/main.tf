# Pull secrets from Infisical
data "infisical_secrets" "nuc" {
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/nuc"
}

locals {
  tailscale_auth_key = data.infisical_secrets.nuc.secrets["TAILSCALE_AUTH_KEY"].value
}

# NUC infra VM — runs all Docker Compose services
module "infra_vm" {
  source = "../modules/proxmox-vm"

  node   = "nuc"
  vm_id  = 200
  name   = "nuc-infra"
  cores  = 2
  memory = 8192 # 8GB
  disk_size = 40

  ssh_public_keys    = var.ssh_public_key
  tailscale_auth_key = local.tailscale_auth_key

  ip_address  = "192.168.0.2/24"
  gateway     = "192.168.0.1"
  dns_servers = ["192.168.0.1"] # use Eero during bootstrap; switch to 192.168.0.2 after AdGuard is up

  tags = ["nuc", "infra", "docker"]

  user_data = file("${path.module}/../../cloud-init/docker-host.yaml")
}

# MinIO VM — S3-compatible object storage, data on Storinator via NFS
module "minio_vm" {
  source = "../modules/proxmox-vm"

  node   = "nuc"
  vm_id  = 201
  name   = "nuc-minio"
  cores  = 2
  memory = 4096 # 4GB
  disk_size = 20

  ssh_public_keys    = var.ssh_public_key
  tailscale_auth_key = local.tailscale_auth_key

  ip_address = "192.168.0.21/24"
  gateway    = "192.168.0.1"

  tags = ["nuc", "minio", "storage"]
}
