module "identity" {
  for_each = var.identities

  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.2"

  enable_telemetry    = false
  location            = var.location
  name                = each.value.name
  resource_group_name = var.resource_group_name
  role_assignments    = each.value.role_assignments
  tags                = var.tags
}
