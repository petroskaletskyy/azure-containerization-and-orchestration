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

# Create a resource group 
resource "azurerm_resource_group" "rg" {
  name     = "task-5-rg"
  location = "North Europe"
}

# Create AKS cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "task-5-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "task-5-aks"
  sku_tier            = "Free"
  kubernetes_version  = "1.30.7"

  default_node_pool {
    name                = "agentpool"
    node_count          = 1
    vm_size             = "Standard_D2_v2"
    enable_auto_scaling = false
  }

  identity {
    type = "SystemAssigned"
  }
}
# Add kubeconfig to local file  
resource "local_file" "kubeconfig" {
  content    = azurerm_kubernetes_cluster.aks.kube_config_raw
  filename   = "${path.module}/.kube/config"
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "null_resource" "check_kubectl" {
  provisioner "local-exec" {
    command = <<EOT
        export KUBECONFIG="${path.module}/.kube/config"
        kubectl get nodes
        kubectl create deployment nginx --image=dockerbogo/docker-nginx-hello-world:latest
        kubectl expose deployment nginx --port=80 --type=LoadBalancer
        sleep 15
        ip=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        echo "The IP address is $ip"
    EOT
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}
