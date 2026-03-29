terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }

  # State stored on Storinator NFS — mount before running Terraform.
  # Mount: sudo mount -t nfs storinator:/mnt/pool/terraform-state /mnt/terraform-state
  backend "local" {
    path = "/mnt/terraform-state/nuc/terraform.tfstate"
  }
}
