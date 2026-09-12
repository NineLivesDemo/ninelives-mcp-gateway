module "hub_and_spoke" {
  # This pattern owns the shared hub capabilities. Spoke VNets are composed
  # separately with the AVM VNet resource module and peer to this hub.
  source  = "Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm"
  version = "0.17.5"

  enable_telemetry = false
  tags             = var.tags

  hub_and_spoke_networks_settings = {
    enabled_resources = {
      ddos_protection_plan = false
    }
  }

  hub_virtual_networks = {
    primary = {
      location                  = var.location
      default_parent_id         = var.hub_resource_group_id
      default_hub_address_space = var.hub_address_space[0]
      enabled_resources = {
        firewall                              = var.enable_firewall
        firewall_policy                       = var.enable_firewall
        bastion                               = var.enable_bastion
        virtual_network_gateway_express_route = false
        virtual_network_gateway_vpn           = false
        private_dns_zones                     = var.enable_private_dns_zones
        private_dns_resolver                  = false
        dns_resolver_policy                   = false
        ddos_protection_plan                  = false
        nat_gateway                           = var.enable_nat_gateway
      }
      hub_virtual_network = {
        name          = var.hub_name
        address_space = var.hub_address_space
        parent_id     = var.hub_resource_group_id
        subnets       = var.hub_subnets
      }
      bastion = var.enable_bastion ? {
        tunneling_enabled = var.enable_bastion_tunneling
      } : null
      nat_gateway = var.enable_nat_gateway ? {} : null
    }
  }
}
