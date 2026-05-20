# versions.tf - Provider requirements and backend configuration
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66.0"
    }
  }
}

# Configure the Proxmox provider
# Auth via API token is recommended over password
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # Skip TLS verification if using self-signed certs
  insecure = var.proxmox_insecure

  ssh {
    agent    = true
    username = "root"
  }
}
