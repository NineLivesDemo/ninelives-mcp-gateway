module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  enable_telemetry = false
  location         = var.location
  name             = var.name
  parent_id        = var.resource_group_id
  address_space    = var.address_space
  peerings = {
    hub = {
      name                               = "${var.name}-to-hub"
      remote_virtual_network_resource_id = var.hub_virtual_network_id
      allow_forwarded_traffic            = true
      create_reverse_peering             = true
      reverse_name                       = "hub-to-${var.name}"
      reverse_allow_forwarded_traffic    = true
    }
  }
  subnets = var.subnets
  tags    = var.tags
}
