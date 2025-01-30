# Define the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create a resource group 
resource "azurerm_resource_group" "rg" {
  name     = "task-3-rg"
  location = "North Europe"
}

# Create container registry
resource "azurerm_container_registry" "acr" {
  name                = "task3acr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Build and push the image to the container registry
resource "null_resource" "build_and_push" {
  provisioner "local-exec" {
    command = <<EOT
        docker rmi -f ${azurerm_container_registry.acr.login_server}/flask-app:v1 || true
        cd /Users/pskaletskyy/Documents/Azure/Task_4/task_3/flask_app
        docker build -t ${azurerm_container_registry.acr.login_server}/flask-app:v1 .
        docker login ${azurerm_container_registry.acr.login_server} -u ${azurerm_container_registry.acr.admin_username} -p ${azurerm_container_registry.acr.admin_password}
        docker push ${azurerm_container_registry.acr.login_server}/flask-app:v1
    EOT
  }
  depends_on = [azurerm_container_registry.acr]
}

resource "random_id" "dns_name" {
  count       = 3
  byte_length = 4
}

# Createa container group 
resource "azurerm_container_group" "container_group" {
  count               = 3
  name                = "flask-container-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"

  container {
    name   = "flask-app"
    image  = "${azurerm_container_registry.acr.login_server}/flask-app:v1"
    cpu    = "0.5"
    memory = "1.5"
    ports {
      port     = 5000
      protocol = "TCP"
    }
  }

  image_registry_credential {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
  }

  ip_address_type = "Public"
  dns_name_label  = "flask-app-${random_id.dns_name[count.index].hex}"

  tags = {
    environment = "development"
  }

  depends_on = [null_resource.build_and_push]
}

output "container_ips" {
  value = [for instance in azurerm_container_group.container_group : "${instance.ip_address}:5000"]
}  