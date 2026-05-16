terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # State stored on Alakazam NFS — mount before running Terraform.
  # Mount: sudo mount -t nfs alakazam.local:/mnt/pool/apps/terraform /mnt/terraform-state
  backend "local" {
    path = "/mnt/terraform-state/diglett/terraform.tfstate"
  }
}
