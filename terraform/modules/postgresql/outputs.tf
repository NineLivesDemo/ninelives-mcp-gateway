output "resource_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = module.server.resource_id
}

output "name" {
  description = "Name of the PostgreSQL Flexible Server."
  value       = module.server.name
}

output "fqdn" {
  description = "Private PostgreSQL server FQDN."
  value       = module.server.fqdn
}
