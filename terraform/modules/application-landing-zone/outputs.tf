output "virtual_network_resource_id" {
  description = "Resource ID of the application landing-zone VNet."
  value       = module.virtual_network.resource_id
}

output "subnet_resource_ids" {
  description = "Resource IDs of the application landing-zone subnets."
  value = {
    for subnet_key, subnet in module.virtual_network.subnets :
    subnet_key => subnet.resource_id
  }
}

output "hub_peering" {
  description = "The bidirectional peering between the application landing-zone VNet and the hub."
  value       = module.virtual_network.peerings["hub"]
}
