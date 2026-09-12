module "connectivity" {
  source = "../connectivity"

  location                 = var.location
  hub_resource_group_id    = var.hub_resource_group_id
  hub_name                 = var.hub_name
  hub_address_space        = var.hub_address_space
  hub_subnets              = var.hub_subnets
  enable_bastion_tunneling = var.enable_bastion_tunneling
  tags                     = var.tags
}

module "ingress_platform_services" {
  source = "../platform-services"

  location               = var.location
  resource_group_id      = var.ingress_resource_group_id
  name                   = var.ingress_vnet_name
  address_space          = var.ingress_address_space
  subnets                = var.ingress_subnets
  hub_virtual_network_id = module.connectivity.hub_virtual_network_resource_id
  tags                   = var.tags
}
