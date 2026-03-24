terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    infisical = {
      source  = "Infisical/infisical"
      version = "~> 0.12"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true
}

provider "infisical" {
  host          = var.infisical_host
  client_id     = var.infisical_client_id
  client_secret = var.infisical_client_secret
}
