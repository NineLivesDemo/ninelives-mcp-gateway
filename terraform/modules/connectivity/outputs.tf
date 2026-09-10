output "hub_virtual_network_resource_id" {
  description = "Resource ID of the platform connectivity hub VNet."
  value       = module.hub_and_spoke.resource_id["primary"]
}

output "bastion_host_resource_id" {
  description = "Resource ID of the hub Bastion host, when enabled."
  value       = try(module.hub_and_spoke.bastion_host_resource_ids["primary"], null)
}

output "nat_gateway_resource_id" {
  description = "Resource ID of the hub NAT Gateway, when enabled."
  value       = try(module.hub_and_spoke.nat_gateway_resource_ids["primary"], null)
}
