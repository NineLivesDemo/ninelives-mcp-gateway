output "hub_virtual_network_resource_id" {
  description = "Resource ID of the platform connectivity hub VNet."
  value       = module.connectivity.hub_virtual_network_resource_id
}

output "ingress_virtual_network_resource_id" {
  description = "Resource ID of the private ingress/platform-services VNet."
  value       = module.ingress_platform_services.virtual_network_resource_id
}

output "ingress_subnet_resource_ids" {
  description = "Resource IDs of subnets in the ingress/platform-services VNet."
  value       = module.ingress_platform_services.subnet_resource_ids
}
