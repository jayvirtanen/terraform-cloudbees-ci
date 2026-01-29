variable "admin_password" {
  default = "prom-operator"
  type    = string
}

variable "host_name" {
  type = string
}

variable "ingress_annotations" {
  default = {}
  type    = map(string)
}

variable "ingress_class_name" {
  type = string
}

variable "ingress_extra_paths" {
  default = null
  type    = list(any)
}

variable "namespace" {
  default = "prometheus"
}

variable "release_name" {
  default = "prometheus"
}
