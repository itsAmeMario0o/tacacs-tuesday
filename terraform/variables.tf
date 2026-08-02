variable "location" {
  description = "Azure region for every lab resource (ADR 0001)"
  type        = string
  default     = "eastus2"
}

variable "owner" {
  description = "Value for the owner tag on every resource"
  type        = string
}

variable "expires" {
  description = "Value for the expires tag, an ISO date like 2026-09-30"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "tacacs-tue"
}

variable "ise_image" {
  description = "Marketplace image for Cisco ISE. Written by scripts/10-resolve-images.sh into images.auto.tfvars, never hardcoded."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "c8000v_image" {
  description = "Marketplace image for the Catalyst 8000V. Written by scripts/10-resolve-images.sh into images.auto.tfvars, never hardcoded."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "ise_vm_size" {
  description = "VM size for ISE. Standard_D8s_v4 (8 vCPU/32 GB) is the smallest instance Cisco supports for ISE on Azure. Smaller sizes let the OS boot but starve the ISE application so the admin GUI never comes up."
  type        = string
  default     = "Standard_D8s_v4"
}

variable "c8000v_vm_size" {
  description = "VM size for the C8000V. Verify against the C8000V Azure guide in Task 5."
  type        = string
  default     = "Standard_DS3_v2"
}

variable "ise_private_ip" {
  description = "Static private IP for ISE inside snet-mgmt. Static so the router day-0 config can reference it."
  type        = string
  default     = "10.80.0.68"
}

variable "dns_server" {
  description = "Azure's virtual DNS IP, the same constant in every VNet"
  type        = string
  default     = "168.63.129.16"
}
