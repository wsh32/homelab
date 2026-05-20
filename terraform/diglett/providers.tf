provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = false

  ssh {
    agent    = true
    username = "root"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
