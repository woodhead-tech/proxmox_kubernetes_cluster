# variables.tf - Input variables for the Proxmox Kubernetes cluster

# --- Proxmox Connection ---

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g., https://pve.example.com:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the format USER@REALM!TOKEN_ID=SECRET"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = false
}

# --- Proxmox Infrastructure ---

variable "proxmox_node" {
  description = "Proxmox node name to deploy VMs on"
  type        = string
}

variable "datastore" {
  description = "Proxmox storage pool for VM disks (Ceph pool)"
  type        = string
  default     = "ceph-pool"
}

variable "talos_iso" {
  description = "Path to Talos ISO on Proxmox storage (e.g., local:iso/talos-amd64.iso)"
  type        = string
  default     = "local:iso/talos-amd64.iso"
}

# --- Network ---

variable "network_bridge" {
  description = "Proxmox network bridge for VM NICs"
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Network gateway IP"
  type        = string
}

variable "network_subnet" {
  description = "Network subnet in CIDR notation (e.g., 24)"
  type        = number
  default     = 24
}

variable "nameservers" {
  description = "DNS nameservers for the cluster nodes"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# --- Cluster Configuration ---

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "talos-proxmox"
}

variable "cluster_vip" {
  description = "Virtual IP for the Kubernetes API server (used by Talos VIP)"
  type        = string
}

# --- Control Plane Nodes ---

variable "controlplane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "controlplane_vmid_start" {
  description = "Starting VM ID for control plane nodes"
  type        = number
  default     = 400
}

variable "controlplane_cores" {
  description = "CPU cores per control plane node"
  type        = number
  default     = 2
}

variable "controlplane_memory" {
  description = "Memory in MB per control plane node (balloon ceiling)"
  type        = number
  default     = 4096
}

variable "controlplane_balloon" {
  description = "Minimum guaranteed RAM in MB per control plane node (balloon floor)"
  type        = number
  default     = 2048
}

variable "controlplane_disk_size" {
  description = "Disk size in GB per control plane node"
  type        = number
  default     = 50
}

variable "controlplane_ips" {
  description = "Static IPs for control plane nodes"
  type        = list(string)
}

variable "controlplane_nodes" {
  description = "Proxmox node name for each control plane VM (index-matched). Falls back to proxmox_node if index not defined."
  type        = list(string)
  default     = []
}

# --- Worker Nodes ---

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_vmid_start" {
  description = "Starting VM ID for worker nodes"
  type        = number
  default     = 410
}

variable "worker_cores" {
  description = "CPU cores per worker node"
  type        = number
  default     = 4
}

variable "worker_memory" {
  description = "Memory in MB per worker node (balloon ceiling)"
  type        = number
  default     = 8192
}

variable "worker_balloon" {
  description = "Minimum guaranteed RAM in MB per worker node (balloon floor)"
  type        = number
  default     = 4096
}

variable "worker_disk_size" {
  description = "Disk size in GB for Talos worker nodes"
  type        = number
  default     = 100
}

variable "talos_iops_read" {
  description = "IOPS read limit for Talos nodes (lowered to 200 for HDD-backed Ceph stability)"
  type        = number
  default     = 200
}

variable "talos_iops_write" {
  description = "IOPS write limit for Talos nodes (lowered to 200 for HDD-backed Ceph stability)"
  type        = number
  default     = 200
}


variable "worker_ips" {
  description = "Static IPs for worker nodes"
  type        = list(string)
}

variable "worker_nodes" {
  description = "Proxmox node name for each worker VM (index-matched). Falls back to proxmox_node if index not defined."
  type        = list(string)
  default     = []
}

# --- Talos ---

variable "talos_version" {
  description = "Talos Linux version to deploy"
  type        = string
  default     = "v1.9.0"
}
