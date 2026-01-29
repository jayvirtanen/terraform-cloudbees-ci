resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "this" {
  depends_on = [kubernetes_namespace_v1.this]

  chart      = "kube-prometheus-stack"
  name       = var.release_name
  namespace  = var.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  values     = [local.values]
}

locals {
  values = yamlencode({
    grafana = {
      adminPassword             = var.admin_password
      defaultDashboardsTimezone = "America/New_York"
      enabled                   = true

      ingress = {
        annotations      = var.ingress_annotations
        enabled          = true
        extraPaths       = var.ingress_extra_paths
        hosts            = [var.host_name]
        ingressClassName = var.ingress_class_name
      }
    }
  })
}
