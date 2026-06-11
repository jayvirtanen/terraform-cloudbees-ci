terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }

    kubernetes = {
      version = ">= 3.0.0"
    }
  }
}
