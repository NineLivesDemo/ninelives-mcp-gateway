module "zone" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  enable_telemetry = false
  domain_name      = var.domain_name
  parent_id        = var.resource_group_id
  virtual_network_links = {
    for link_key, virtual_network_id in var.virtual_network_ids :
    link_key => {
      name               = "${var.domain_name}-${link_key}"
      virtual_network_id = virtual_network_id
    }
  }
  tags = var.tags
}
