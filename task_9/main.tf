# Define the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.93.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# Create a resource group 
resource "azurerm_resource_group" "rg" {
  name     = "task-9-rg"
  location = "North Europe"
}

# Create container registry
resource "azurerm_container_registry" "acr" {
  name                = "task9acrflaskapp"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Build and push the image to the container registry
resource "null_resource" "build_and_push" {
  provisioner "local-exec" {
    command = <<EOT
        docker rmi -f ${azurerm_container_registry.acr.login_server}/flask-app:lite || true
        cd /Users/pskaletskyy/Documents/Azure/Task_4/task_9/flask_app:lite
        docker build -t ${azurerm_container_registry.acr.login_server}/flask-app:lite .
        docker login ${azurerm_container_registry.acr.login_server} -u ${azurerm_container_registry.acr.admin_username} -p ${azurerm_container_registry.acr.admin_password}
        docker push ${azurerm_container_registry.acr.login_server}/flask-app:lite
        docker rmi -f ${azurerm_container_registry.acr.login_server}/flask-app:full || true
        cd /Users/pskaletskyy/Documents/Azure/Task_4/task_9/flask_app:full
        docker build -t ${azurerm_container_registry.acr.login_server}/flask-app:full .
        docker push ${azurerm_container_registry.acr.login_server}/flask-app:full
    EOT
  }
  depends_on = [azurerm_container_registry.acr]
}

# Create AKS cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "task-9-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "task-9-aks"
  sku_tier            = "Free"
  kubernetes_version  = "1.30.7"

  default_node_pool {
    name       = "agentpool"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  role_based_access_control_enabled = true

  identity {
    type = "SystemAssigned"
  }
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.rg.name
}

# Grant AKS access to the container registry    
resource "azurerm_role_assignment" "acr_role" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

resource "local_file" "kubeconfig" {
  content    = azurerm_kubernetes_cluster.aks.kube_config_raw
  filename   = "${path.module}/.kube/config"
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "null_resource" "check_kubectl" {
  provisioner "local-exec" {
    command = <<EOT
        export KUBECONFIG="${path.module}/.kube/config"
    EOT
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Deploy the Application to AKS
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "flask-app"
    namespace = "default"
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "flask-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "flask-app"
        }
      }
      spec {
        container {
          name  = "flask-app"
          image = "${azurerm_container_registry.acr.login_server}/flask-app:lite"
          port {
            container_port = 5000
          }
        }
      }
    }
  }
}

# Expose the Application via LoadBalancer
resource "kubernetes_service" "app_service" {
  metadata {
    name      = "flask-app-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "flask-app"
    }
    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5000
    }
    type = "LoadBalancer"
  }
}

# Get the Public IP of the Application
output "app_service_ip" {
  value = kubernetes_service.app_service.status.0.load_balancer.0.ingress.0.ip
}