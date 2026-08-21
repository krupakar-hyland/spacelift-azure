terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  skip_provider_registration = false

  # When using Spacelift with federated credentials, authentication is automatic
  # The provider will use the OIDC token passed by Spacelift
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name       = var.resource_group_name
  location   = var.location

  tags = var.common_tags
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  shared_access_key_enabled        = true
  public_network_access_enabled    = true

  tags = var.common_tags
}

# Storage Container (optional example)
resource "azurerm_storage_container" "main" {
  name                  = var.storage_container_name
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}
