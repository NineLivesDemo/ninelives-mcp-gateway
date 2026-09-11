resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = each.value.network_security_group_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "inbound" {
  for_each = {
    for rule in flatten([
      for subnet_key, subnet in var.subnets : [
        for rule in subnet.inbound_rules : merge(rule, {
          key        = "${subnet_key}-${rule.name}"
          subnet_key = subnet_key
        })
      ]
    ]) : rule.key => rule
  }

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this[each.value.subnet_key].name
}

resource "azurerm_route_table" "this" {
  for_each = var.subnets

  name                          = each.value.route_table_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = true
  tags                          = var.tags
}

resource "azurerm_route" "custom" {
  for_each = {
    for route in flatten([
      for subnet_key, subnet in var.subnets : [
        for route in subnet.routes : merge(route, {
          key        = "${subnet_key}-${route.name}"
          subnet_key = subnet_key
        })
      ]
    ]) : route.key => route
  }

  name                   = each.value.name
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this[each.value.subnet_key].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = each.value.next_hop_in_ip_address
}

removed {
  from = azurerm_subnet_network_security_group_association.this

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_subnet_route_table_association.this

  lifecycle {
    destroy = false
  }
}
