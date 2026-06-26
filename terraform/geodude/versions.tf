terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.109"
    }
  }

  # State stored on Alakazam NFS -- mount before running Terraform.
  # Mount: sudo mount -t nfs alakazam.local:/mnt/apps/terraform /mnt/terraform-state
  backend "local" {
    path = "/mnt/terraform-state/geodude/terraform.tfstate"
  }
}
