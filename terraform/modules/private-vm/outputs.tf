output "resource_id" {
  description = "Resource ID of the VM."
  value       = module.virtual_machine.resource_id
}

output "network_interface_ids" {
  description = "Network interface resource IDs."
  value = {
    for nic_key, nic in module.virtual_machine.network_interfaces :
    nic_key => nic.id
  }
}

output "private_ip_address" {
  description = "Primary private IPv4 address of the VM."
  value       = module.virtual_machine.virtual_machine_azurerm.private_ip_address
}
