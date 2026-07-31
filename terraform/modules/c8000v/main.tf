resource "azurerm_network_interface" "c8000v" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "c8000v" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.c8000v.id]
  tags                            = var.tags

  custom_data = base64encode(templatefile("${path.module}/templates/day0.cfg.tftpl", {
    hostname       = var.name
    domain_name    = var.domain_name
    admin_username = var.admin_username
    admin_password = var.admin_password
    ise_ip         = var.ise_ip
    tacacs_secret  = var.tacacs_secret
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  plan {
    name      = var.image.sku
    product   = var.image.offer
    publisher = var.image.publisher
  }
}
