
# Terraform Provider Configuration

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 4.0, < 6.0"
    }

    random = {
      source = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
  }

}

## Terraform Azure Provider

provider "azurerm" {
  features {
    key_vault {
      recover_soft_deleted_key_vaults       = true
      recover_soft_deleted_secrets          = true
      purge_soft_delete_on_destroy          = true
      purge_soft_deleted_secrets_on_destroy = true
    }
  }
}
