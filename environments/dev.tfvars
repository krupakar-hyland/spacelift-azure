location                          = "eastus"
resource_group_name               = "rg-spacelift-demo-dev"
storage_account_name              = "stspldemodev001"
storage_account_tier              = "Standard"
storage_account_replication_type  = "LRS"
storage_container_name            = "data"

common_tags = {
  Environment = "dev"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo"
}
