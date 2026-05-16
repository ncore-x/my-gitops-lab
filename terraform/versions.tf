terraform {
    required_providers {
        kubernetes = {
            source = "hashicorp/kubernetes"
            version = "~> 2.25"
        }
        helm = {
            source = "hashicorp/helm"
            version = "~> 2.12"
        }
        null = {
            source  = "hashicorp/null"
            version = "~> 3.0"
        }
    }
}

provider "kubernetes" {
    config_path = "~/.kube/config"
    config_context = "minikube"
}

provider "helm" {
    kubernetes {
        config_path = "~/.kube/config"
        config_context = "minikube"
    }
}
