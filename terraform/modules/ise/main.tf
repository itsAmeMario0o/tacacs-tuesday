resource "azurerm_network_interface" "ise" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip
  }
}

# Cisco's Azure image authenticates the CLI user with an SSH key, not a
# password. The key is generated here so a rebuild never depends on state
# outside Terraform (ADR 0004).
resource "tls_private_key" "ise" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "ise" {
  name                  = var.name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.ise.id]
  tags                  = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ise.public_key_openssh
  }

  # ISE 3.4 reads its day-0 bootstrap from user_data, matching Cisco's own
  # Azure Terraform. The setup reads user_data via IMDS during first boot.
  # Field names are ISE-specific (e.g. primaryntpserver, not ntpserver) and
  # each key=value goes on its own line.
  user_data = base64encode(templatefile("${path.module}/templates/userdata.txt.tftpl", {
    hostname       = var.name
    dns_server     = var.dns_server
    domain_name    = var.domain_name
    ntp_server     = var.ntp_server
    admin_password = var.admin_password
  }))

  # Managed-storage boot diagnostics so a failed first boot leaves a
  # readable serial console.
  boot_diagnostics {}

  # Premium SSD per Cisco's ISE-on-Azure sizing guidance. ISE's first-boot
  # database init is IO-bound and crawls on StandardSSD, leaving the admin
  # GUI unavailable for hours.
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_gb
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
