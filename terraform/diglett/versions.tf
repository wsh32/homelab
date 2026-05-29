terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0.0"
    }
  }

  # TODO(C4): migrate to an S3/Minio backend with locking (or Terraform Cloud free tier).
  # Current local backend has no concurrent-write locking and stores secrets in plaintext.
  # State stored on Alakazam NFS — mount before running Terraform.
  # Mount: sudo mount -t nfs alakazam.local:/mnt/apps/terraform /mnt/terraform-state
  backend "local" {
    path = "/mnt/terraform-state/diglett/terraform.tfstate"
  }
}
