location                 = "eastus"
resource_group_name      = "rg-spacelift-demo-network-prod"
vnet_name                = "vnet-spacelift-demo-prod"
vnet_address_space       = ["10.2.0.0/16"]
subnet_name              = "snet-app-prod"
subnet_address_prefixes  = ["10.2.1.0/24"]

common_tags = {
  Environment = "production"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo-Networking"
}
