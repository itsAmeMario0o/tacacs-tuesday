variable "name" {
  description = "Bastion host name. CLAUDE.md tunnel commands assume bas-lab."
  type        = string
  default     = "bas-lab"
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "bastion_subnet_id" {
  description = "ID of AzureBastionSubnet"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}
