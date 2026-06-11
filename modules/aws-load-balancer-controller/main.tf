locals {
  name_prefix = "${var.cluster_name}_${var.release_name}"
  namespace   = "kube-system"
  role_name   = substr(local.name_prefix, 0, 38)

  values = yamlencode({
    clusterName                = var.cluster_name
    createIngressClassResource = true

    serviceAccount = {
      name = var.service_account_name
      annotations = {
        "eks.amazonaws.com/role-arn" : module.service_account_role.arn
      }
    }
  })
}

module "service_account_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.4.0"

  name            = local.role_name
  use_name_prefix = true

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_arn
      namespace_service_accounts = ["${local.namespace}:${var.service_account_name}"]
    }
  }
}

# Install Gateway API resource from manifests due to issue with Helm and the experimental releases
data "http" "experimental" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v${var.gateway_version}/experimental-install.yaml"
}

data "kubectl_file_documents" "experimental" {
  content = data.http.experimental.response_body
}

resource "kubectl_manifest" "experimental" {
  for_each = data.kubectl_file_documents.experimental.manifests

  force_conflicts   = true
  server_side_apply = true
  yaml_body         = each.value
}

# Install Gateway API-specific CRDs for AWS LBC
data "http" "lbc-gateway" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml"
}

data "kubectl_file_documents" "lbc-gateway" {
  content = data.http.lbc-gateway.response_body
}

resource "kubectl_manifest" "lbc-gateway" {
  depends_on = [kubectl_manifest.experimental]
  for_each   = data.kubectl_file_documents.lbc-gateway.manifests
  yaml_body  = each.value
}

resource "helm_release" "this" {
  depends_on = [kubectl_manifest.lbc-gateway]

  chart      = "aws-load-balancer-controller"
  name       = var.release_name
  namespace  = local.namespace
  repository = "https://aws.github.io/eks-charts"
  values     = [local.values]
  version    = var.chart_version
}

resource "kubernetes_manifest" "gateway_class" {
  depends_on = [helm_release.this]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "GatewayClass"
    metadata = {
      name = var.gateway_class_name
    }
    spec = {
      controllerName = "gateway.k8s.aws/alb"
    }
  }
}
