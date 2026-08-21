output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.network.id
}

output "vnet_id" {
  description = "ID of the created virtual network"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "ID of the created subnet"
  value       = azurerm_subnet.app.id
}
