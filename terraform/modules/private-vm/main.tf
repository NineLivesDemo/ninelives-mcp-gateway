module "virtual_machine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.21.0"

  enable_telemetry           = false
  location                   = var.location
  name                       = var.name
  resource_group_name        = var.resource_group_name
  zone                       = var.zone
  os_type                    = "Linux"
  sku_size                   = var.sku_size
  encryption_at_host_enabled = false
  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  account_credentials = {
    admin_credentials = {
      username                           = var.admin_username
      ssh_keys                           = [var.ssh_public_key]
      generate_admin_password_or_ssh_key = false
    }
    password_authentication_disabled = true
  }
  managed_identities = {
    user_assigned_resource_ids = var.user_assigned_identity_ids
  }
  network_interfaces = {
    primary = {
      name       = "${var.name}-nic"
      is_primary = true
      ip_configurations = {
        primary = {
          name                          = "primary"
          private_ip_address_allocation = "Dynamic"
          private_ip_subnet_resource_id = var.subnet_resource_id
          create_public_ip_address      = false
        }
      }
    }
  }
  tags = var.tags
}
