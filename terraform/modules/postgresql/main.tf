module "server" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "0.2.3"

  enable_telemetry                  = false
  location                          = var.location
  name                              = var.name
  resource_group_name               = var.resource_group_name
  administrator_login               = var.administrator_login
  administrator_password_wo         = var.administrator_password
  administrator_password_wo_version = var.administrator_password_version
  authentication = {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }
  backup_retention_days         = 7
  firewall_rules                = {}
  high_availability             = null
  private_dns_zone_id           = null
  public_network_access_enabled = false
  server_version                = "16"
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  private_endpoints = {
    primary = {
      name                          = "${var.name}-private-endpoint"
      subnet_resource_id            = var.private_endpoint_subnet_id
      private_dns_zone_resource_ids = [var.private_dns_zone_id]
    }
  }
  tags = var.tags
}
