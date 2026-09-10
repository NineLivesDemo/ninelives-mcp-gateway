output "network_security_group_ids" {
  description = "Network security group IDs keyed by protected subnet."
  value = {
    for subnet_key, nsg in azurerm_network_security_group.this :
    subnet_key => nsg.id
  }
}

output "route_table_ids" {
  description = "Route table IDs keyed by protected subnet."
  value = {
    for subnet_key, route_table in azurerm_route_table.this :
    subnet_key => route_table.id
  }
}
