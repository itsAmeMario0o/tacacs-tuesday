# ISE parses its admin password from a key=value line in custom_data, where
# "#" begins a comment and would truncate the value. Restrict specials to a
# single safe character that ISE accepts and the parser leaves intact.
resource "random_password" "ise_admin" {
  length           = 16
  special          = true
  override_special = "@"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Azure enforces three of four character classes on admin_password.
# Force one of each present class so no rebuild draws an all-one-class
# password and fails at apply (ADR 0004 rebuild reliability).
resource "random_password" "c8000v_admin" {
  length      = 16
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "tacacs_secret" {
  length  = 24
  special = false
}

module "foundation" {
  source = "./modules/foundation"

  name_prefix = var.name_prefix
  location    = var.location
  tags        = local.common_tags
}

module "bastion" {
  source = "./modules/bastion"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  bastion_subnet_id   = module.foundation.bastion_subnet_id
  tags                = local.common_tags
}

module "ise" {
  source = "./modules/ise"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  subnet_id           = module.foundation.mgmt_subnet_id
  private_ip          = var.ise_private_ip
  vm_size             = var.ise_vm_size
  image               = var.ise_image
  admin_password      = random_password.ise_admin.result
  dns_server          = var.dns_server
  tags                = local.common_tags
}

module "c8000v" {
  source = "./modules/c8000v"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  subnet_id           = module.foundation.nad_subnet_id
  vm_size             = var.c8000v_vm_size
  image               = var.c8000v_image
  admin_password      = random_password.c8000v_admin.result
  tacacs_secret       = random_password.tacacs_secret.result
  ise_ip              = var.ise_private_ip
  tags                = local.common_tags
}
