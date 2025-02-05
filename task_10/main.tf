# Define the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.93.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">=1.14.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# Create a resource group 
resource "azurerm_resource_group" "rg" {
  name     = "task-10-rg"
  location = "North Europe"
}

# Create AKS cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "task-10-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "task-10-aks"
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

data "azurerm_container_registry" "acr" {
  name                = "testacrflaskapp"
  resource_group_name = "acr-rg"
}

# Grant AKS access to the container registry    
resource "azurerm_role_assignment" "acr_role" {
  scope                = data.azurerm_container_registry.acr.id
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
        kubectl --kubeconfig="${path.module}/.kube/config" get pods
    EOT
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "kubectl" {
  config_path = local_file.kubeconfig.filename
}

# Install ArgoCD using Helm
provider "helm" {
  kubernetes {
    config_path            = local_file.kubeconfig.filename
    host                   = data.azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.8.0"

  values = [
    <<EOF
server:
  service:
    type: LoadBalancer
EOF        
  ]
  depends_on = [azurerm_kubernetes_cluster.aks]
}

resource "kubectl_manifest" "gitops-app" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: "https://github.com/petroskaletskyy/git-ops-test-repo.git"
    targetRevision: HEAD
    path: manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true  
YAML
  depends_on = [helm_release.argocd]
}

data "kubernetes_service" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_public_ip" {
  value = data.kubernetes_service.argocd.status[0].load_balancer[0].ingress[0].ip
}

# Retrieve ArgoCD Admin Password
data "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }
  depends_on = [helm_release.argocd]
}

output "argocd_admin_password" {
  value     = data.kubernetes_secret.argocd_admin_password.data["password"]
  sensitive = true
}