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

resource "null_resource" "gateway_api" {
  provisioner "local-exec" {
    command = <<EOF
#Experimental Gateway API CRDs [OPTIONAL: Used for L4 Routes]
kubectl apply --force-conflicts --server-side=true \
    -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v${var.gateway_version}/experimental-install.yaml

#Installation of LBC Gateway API specific CRDs
kubectl apply \
    -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml
EOF
  }
}

resource "helm_release" "this" {
  depends_on = [null_resource.gateway_api]

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
