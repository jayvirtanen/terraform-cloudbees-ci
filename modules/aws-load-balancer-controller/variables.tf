variable "chart_version" {
  default = "3.0.0"
}

variable "cluster_name" {
  type = string
}

variable "oidc_arn" {
  type = string
}

variable "release_name" {
  default = "aws-load-balancer-controller"
  type    = string
}

variable "service_account_name" {
  default = "aws-load-balancer-controller"
  type    = string
}
