# Define the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.9.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# Create a resource group 
resource "azurerm_resource_group" "rg" {
  name     = "task-4-rg"
  location = "North Europe"
}

# Create container registry
resource "azurerm_container_registry" "acr" {
  name                = "task4acrvault"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Build and push the image to the container registry
resource "null_resource" "build_and_push" {
  provisioner "local-exec" {
    command = <<EOT
        podman rmi -f ${azurerm_container_registry.acr.login_server}/flask-vault:v1 || true
        cd /Users/pskaletskyy/Documents/Azure/Task_4/task_4/flask_app
        podman build -t ${azurerm_container_registry.acr.login_server}/flask-vault:v1 .
        podman login ${azurerm_container_registry.acr.login_server} -u ${azurerm_container_registry.acr.admin_username} -p ${azurerm_container_registry.acr.admin_password}
        podman push ${azurerm_container_registry.acr.login_server}/flask-vault:v1
    EOT
  }
  depends_on = [azurerm_container_registry.acr]
}

# Create Azure Key Vault   
resource "azurerm_key_vault" "key_vault" {
  name                = "key-vault-task-4-1234"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_rbac_authorization = true
}

# Create iam role assignment
resource "azurerm_role_assignment" "key_vault" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Create a secret in the key vault  
resource "azurerm_key_vault_secret" "secret" {
  name         = "MySecret"
  value        = "SuperSecretValue123!"
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [ azurerm_role_assignment.key_vault ]
}

# Assign Key Vault Access to ACI Managed Identity
resource "azurerm_role_assignment" "aci_kv_access" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_group.container_group.identity[0].principal_id
}

# Createa container group 
resource "azurerm_container_group" "container_group" {
  name                = "flask-container"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"

  identity {
    type = "SystemAssigned"
  }

  container {
    name   = "flask-vault"
    image  = "${azurerm_container_registry.acr.login_server}/flask-vault:v1"
    cpu    = "0.5"
    memory = "1.5"
    ports {
      port     = 5000
      protocol = "TCP"
    }
    environment_variables = {
      "KEY_VAULT_NAME" = azurerm_key_vault.key_vault.name
      "SECRET_NAME"    = azurerm_key_vault_secret.secret.name
    }
  }

  image_registry_credential {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
  }

  ip_address_type = "Public"

  tags = {
    environment = "development"
  }

  depends_on = [null_resource.build_and_push]
}

output "public_ip" {
  value = "${azurerm_container_group.container_group.ip_address}:5000"
}