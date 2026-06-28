provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  ssh {
    agent    = true
    username = "root"
    node {
      name    = "geodude"
      address = "geodude.corgi-census.ts.net"
      port    = 22
    }
  }
}
