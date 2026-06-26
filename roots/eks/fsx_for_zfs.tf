data "aws_vpc" "cluster_vpc" {
  id = module.vpc.id
}


module "fsx_openzfs" {
  source  = "terraform-aws-modules/fsx/aws//modules/openzfs"
  version = "~> 1.3"

  name                = "${var.cluster_name}-openzfs"
  storage_capacity    = 64
  throughput_capacity = 64
  deployment_type     = "SINGLE_AZ_1"
  subnet_ids          = [module.vpc.private_subnet_ids[0]]

  # Leverage the module's built-in security group builder
  create_security_group = true
  security_group_name   = "${var.cluster_name}-fsx-openzfs-sg"
}

# Attach EKS cluster rules to the module-created security group
locals {
  fsx_ports = [
    { port = 111, proto = "tcp", desc = "RPC for NFS" },
    { port = 111, proto = "udp", desc = "RPC for NFS" },
    { port = 2049, proto = "tcp", desc = "NFS server daemon" },
    { port = 2049, proto = "udp", desc = "NFS server daemon" },
  ]
}

resource "aws_security_group_rule" "fsx_ingress_fixed" {
  for_each                 = { for idx, val in local.fsx_ports : idx => val }
  type                     = "ingress"
  from_port                = each.value.port
  to_port                  = each.value.port
  protocol                 = each.value.proto
  description              = each.value.desc
  security_group_id        = module.fsx_openzfs.security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "fsx_ingress_mount_tcp" {
  type                     = "ingress"
  from_port                = 20001
  to_port                  = 20003
  protocol                 = "tcp"
  description              = "NFS mount, status monitor, and lock daemon (TCP)"
  security_group_id        = module.fsx_openzfs.security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "fsx_ingress_mount_udp" {
  type                     = "ingress"
  from_port                = 20001
  to_port                  = 20003
  protocol                 = "udp"
  description              = "NFS mount, status monitor, and lock daemon (UDP)"
  security_group_id        = module.fsx_openzfs.security_group_id
  source_security_group_id = module.eks.node_security_group_id
}



data "aws_iam_policy_document" "fsx_openzfs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:fsx-openzfs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fsx_openzfs_csi" {
  name               = "${var.cluster_name}-fsx-openzfs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.fsx_openzfs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "fsx_openzfs_csi" {
  role       = aws_iam_role.fsx_openzfs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonFSxFullAccess"
}


resource "helm_release" "fsx_openzfs_csi_driver" {
  name       = "aws-fsx-openzfs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-fsx-openzfs-csi-driver"
  chart      = "aws-fsx-openzfs-csi-driver"
  namespace  = "kube-system"

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create = true
          name   = "fsx-openzfs-csi-controller-sa"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.fsx_openzfs_csi.arn
          }
        }
      }
    })
  ]
}



resource "kubernetes_storage_class_v1" "fsx_openzfs" {
  metadata {
    name = "fsx-openzfs-sc"
  }

  storage_provisioner = "fsx.openzfs.csi.aws.com"
  reclaim_policy      = "Delete"

  parameters = {
    ResourceType        = "volume"
    ParentVolumeId      = module.fsx_openzfs.file_system_root_volume_id
    DataCompressionType = "LZ4"
    NfsExports = jsonencode([
      {
        ClientConfigurations = [
          {
            Clients = data.aws_vpc.cluster_vpc.cidr_block
            Options = ["rw", "crossmnt", "no_root_squash"]
          }
        ]
      }
    ])
    OptionsOnDeletion = jsonencode(["DELETE_CHILD_VOLUMES_AND_SNAPSHOTS"])
  }

  mount_options = [
    "nfsvers=4.1",
    "rsize=1048576",
    "wsize=1048576",
    "timeo=600",
    "nconnect=16"
  ]

  depends_on = [helm_release.fsx_openzfs_csi_driver]
}
