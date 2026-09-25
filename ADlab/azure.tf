
# Terraform Provider Configuration

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }

    random = {
      source = "hashicorp/random"
    }
  }

}

## Terraform Azure Provider

provider "azurerm" {
  features {}
}

