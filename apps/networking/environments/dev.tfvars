location                 = "eastus"
resource_group_name      = "rg-spacelift-demo-network-dev"
vnet_name                = "vnet-spacelift-demo-dev"
vnet_address_space       = ["10.0.0.0/16"]
subnet_name              = "snet-app-dev"
subnet_address_prefixes  = ["10.0.1.0/24"]

common_tags = {
  Environment = "dev"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo-Networking"
}
