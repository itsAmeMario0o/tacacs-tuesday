variable "name" {
  description = "VM and hostname for the router"
  type        = string
  default     = "c8kv-lab"
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "ID of snet-nad"
  type        = string
}

variable "vm_size" {
  description = "VM size, verified against the C8000V Azure guide"
  type        = string
}

variable "image" {
  description = "Marketplace image coordinates from images.auto.tfvars"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "admin_username" {
  description = "Local IOS user, the AAA fallback account"
  type        = string
  default     = "labadmin"
}

variable "admin_password" {
  description = "Password for the local IOS user"
  type        = string
  sensitive   = true
}

variable "tacacs_secret" {
  description = "TACACS+ shared secret, must match the ISE network device entry"
  type        = string
  sensitive   = true
}

variable "ise_ip" {
  description = "Private IP of the ISE VM, the TACACS+ server address"
  type        = string
}

variable "domain_name" {
  description = "IP domain name, required before SSH keys can generate"
  type        = string
  default     = "lab.internal"
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}
