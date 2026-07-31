variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}

variable "vnet_cidr" {
  description = "Address space for the lab VNet (ADR 0001)"
  type        = string
  default     = "10.80.0.0/24"
}

variable "bastion_subnet_cidr" {
  description = "AzureBastionSubnet range"
  type        = string
  default     = "10.80.0.0/26"
}

variable "mgmt_subnet_cidr" {
  description = "snet-mgmt range, holds ISE"
  type        = string
  default     = "10.80.0.64/26"
}

variable "nad_subnet_cidr" {
  description = "snet-nad range, holds the C8000V"
  type        = string
  default     = "10.80.0.128/26"
}
