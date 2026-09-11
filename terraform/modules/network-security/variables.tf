variable "location" {
  description = "Azure region for the network security resources."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that owns the network security resources."
  type        = string
}

variable "subnets" {
  description = "Private VM subnet policies and their network resources."
  type = map(object({
    network_security_group_name = string
    route_table_name            = string
    inbound_rules = list(object({
      name                   = string
      priority               = number
      access                 = string
      protocol               = string
      source_address_prefix  = string
      destination_port_range = string
    }))
    routes = list(object({
      name                   = string
      address_prefix         = string
      next_hop_type          = string
      next_hop_in_ip_address = optional(string)
    }))
  }))
}

variable "tags" {
  description = "Tags applied to network security resources."
  type        = map(string)
  default     = {}
}
