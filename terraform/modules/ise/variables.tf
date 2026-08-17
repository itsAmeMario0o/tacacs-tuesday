variable "name" {
  description = "VM and hostname for ISE"
  type        = string
  default     = "ise-lab"
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
  description = "ID of snet-mgmt"
  type        = string
}

variable "private_ip" {
  description = "Static private IP, referenced by the router day-0 config"
  type        = string
}

variable "vm_size" {
  description = "VM size, verified against the ISE cloud guide"
  type        = string
}

variable "os_disk_gb" {
  description = "OS disk size. ISE on Azure needs at least 300 GB; verify in Task 6 Step 1."
  type        = number
  default     = 300
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
  description = "CLI admin user. Cisco's Azure image expects iseadmin."
  type        = string
  default     = "iseadmin"
}

variable "admin_password" {
  description = "ISE GUI admin password, set through user data"
  type        = string
  sensitive   = true
}

variable "dns_server" {
  description = "DNS server handed to ISE"
  type        = string
}

variable "ntp_server" {
  description = "NTP server handed to ISE"
  type        = string
  default     = "time.windows.com"
}

variable "domain_name" {
  description = "DNS domain for the ISE node"
  type        = string
  default     = "tacacs.lab"
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}
