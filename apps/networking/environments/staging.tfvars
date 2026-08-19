location                 = "eastus"
resource_group_name      = "rg-spacelift-demo-network-staging"
vnet_name                = "vnet-spacelift-demo-staging"
vnet_address_space       = ["10.1.0.0/16"]
subnet_name              = "snet-app-staging"
subnet_address_prefixes  = ["10.1.1.0/24"]

common_tags = {
  Environment = "staging"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo-Networking"
}
