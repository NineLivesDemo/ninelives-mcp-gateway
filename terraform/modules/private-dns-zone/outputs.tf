output "resource_id" {
  description = "Resource ID of the private DNS zone."
  value       = module.zone.resource_id
}

output "virtual_network_links" {
  description = "Private DNS zone virtual network links."
  value       = module.zone.virtual_network_link_outputs
}
