# ------------------------------------------------------------
# EKS Variables
# ------------------------------------------------------------

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "aims-dev-eks"
}

variable "eks_version" {
  description = "EKS Kubernetes version. null means AWS default."
  type        = string
  default     = null
}

variable "eks_public_subnet_names" {
  description = "Public subnet names for EKS and external ALB"
  type        = list(string)

  default = [
    "aims-vpc-subnet-public1-ap-northeast-2a",
    "aims-vpc-subnet-public2-ap-northeast-2b"
  ]
}

variable "eks_private_subnet_names" {
  description = "Private subnet names for EKS cluster"
  type        = list(string)

  default = [
    "aims-vpc-subnet-private1-ap-northeast-2a",
    "aims-vpc-subnet-private2-ap-northeast-2b"
  ]
}

variable "eks_node_subnet_names" {
  description = "Private subnet names for EKS managed node group"
  type        = list(string)

  default = [
    "aims-vpc-subnet-private1-ap-northeast-2a",
    "aims-vpc-subnet-private2-ap-northeast-2b"
  ]
}

variable "eks_node_instance_types" {
  description = "EKS node group instance types"
  type        = list(string)
  default     = ["m5.large"]
}

variable "eks_node_desired_size" {
  type    = number
  default = 2
}

variable "eks_node_min_size" {
  type    = number
  default = 0
}

variable "eks_node_max_size" {
  type    = number
  default = 3
}

# ------------------------------------------------------------
# Subnet Data
# ------------------------------------------------------------

data "aws_subnets" "eks_public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = var.eks_public_subnet_names
  }
}

data "aws_subnets" "eks_private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = var.eks_private_subnet_names
  }
}

data "aws_subnets" "eks_nodes" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = var.eks_node_subnet_names
  }
}

# ------------------------------------------------------------
# EKS Subnet Tags
# AWS Load Balancer Controller subnet auto discovery
# ------------------------------------------------------------

resource "aws_ec2_tag" "eks_public_cluster" {
  for_each    = toset(data.aws_subnets.eks_public.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.eks_cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "eks_public_elb" {
  for_each    = toset(data.aws_subnets.eks_public.ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "eks_private_cluster" {
  for_each    = toset(data.aws_subnets.eks_private.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.eks_cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "eks_private_internal_elb" {
  for_each    = toset(data.aws_subnets.eks_private.ids)
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# ------------------------------------------------------------
# EKS Cluster IAM Role
# ------------------------------------------------------------

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.eks_cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ------------------------------------------------------------
# EKS Node IAM Role
# ------------------------------------------------------------

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${var.eks_cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "eks_node_ebs_csi" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------

resource "aws_eks_cluster" "aims" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = concat(
      data.aws_subnets.eks_public.ids,
      data.aws_subnets.eks_private.ids
    )

    endpoint_public_access  = true
    endpoint_private_access = true

    # 현재 PC IP만 EKS API Public Endpoint 접근 허용
    public_access_cidrs = [var.my_ip]
  }

  tags = merge(local.common_tags, {
    Name = var.eks_cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster
  ]
}

# ------------------------------------------------------------
# Node Security Group Rules
# 기존 aws_security_group.eks_nodes를 실제 Node Group에 붙이기 때문에
# Control Plane <-> Node 통신 규칙을 추가
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_cluster_443" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow EKS control plane to nodes HTTPS"
  referenced_security_group_id = aws_eks_cluster.aims.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_cluster_9443" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow EKS control plane to webhook pods"
  referenced_security_group_id = aws_eks_cluster.aims.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 9443
  to_port                      = 9443
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_cluster_10250" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow EKS control plane to kubelet"
  referenced_security_group_id = aws_eks_cluster.aims.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
}

resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_nodes_443" {
  security_group_id            = aws_eks_cluster.aims.vpc_config[0].cluster_security_group_id
  description                  = "Allow nodes to EKS cluster security group"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# ------------------------------------------------------------
# Launch Template
# Node Group에 기존 EKS Node SG를 실제로 부착
# ------------------------------------------------------------

resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.eks_cluster_name}-node-"

  vpc_security_group_ids = [
    aws_security_group.eks_nodes.id,
    aws_eks_cluster.aims.vpc_config[0].cluster_security_group_id
  ]

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name                                            = "${var.eks_cluster_name}-node"
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.common_tags, {
      Name = "${var.eks_cluster_name}-node-volume"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------
# EKS Managed Node Group
# m5.large x 2
# ------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.aims.name
  node_group_name = "${var.eks_cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = data.aws_subnets.eks_nodes.ids

  instance_types = var.eks_node_instance_types
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }
  
  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  labels = {
    env  = var.env
    role = "general"
  }

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-node-group"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
    aws_iam_role_policy_attachment.eks_node_ssm,
    aws_iam_role_policy_attachment.eks_node_ebs_csi,
    aws_vpc_security_group_ingress_rule.eks_nodes_from_cluster_443,
    aws_vpc_security_group_ingress_rule.eks_nodes_from_cluster_9443,
    aws_vpc_security_group_ingress_rule.eks_nodes_from_cluster_10250,
    aws_vpc_security_group_ingress_rule.eks_cluster_from_nodes_443
  ]
}

# ------------------------------------------------------------
# EKS Add-ons
# ------------------------------------------------------------

resource "aws_eks_addon" "before_nodes" {
  for_each = toset([
    "vpc-cni",
    "kube-proxy"
  ])

  cluster_name                = aws_eks_cluster.aims.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "after_nodes" {
  for_each = toset([
    "coredns",
    "aws-ebs-csi-driver"
  ])

  cluster_name                = aws_eks_cluster.aims.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = each.value == "aws-ebs-csi-driver" ? aws_iam_role.ebs_csi_driver.arn : null

  timeouts {
    create = "40m"
    update = "40m"
    delete = "20m"
  }

  tags = local.common_tags

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_driver
  ]
}

# ------------------------------------------------------------
# OIDC Provider for IRSA
# AWS Load Balancer Controller용
# ------------------------------------------------------------

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.aims.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.aims.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
  ]

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-oidc"
  })
}

locals {
  eks_oidc_provider = replace(aws_eks_cluster.aims.identity[0].oidc[0].issuer, "https://", "")
}

# ------------------------------------------------------------
# EBS CSI Driver IAM Role for IRSA
# ServiceAccount: kube-system/ebs-csi-controller-sa
# ------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.eks_cluster_name}-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-ebs-csi-driver-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ------------------------------------------------------------
# AWS Load Balancer Controller IAM Role
# iam_policy_lbc.json 파일은 CMD에서 먼저 다운로드해야 함
# ------------------------------------------------------------

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${var.eks_cluster_name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-alb-controller-role"
  })
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name   = "${var.eks_cluster_name}-alb-controller-policy"
  policy = file("${path.module}/iam_policy_lbc.json")

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

output "eks_cluster_name" {
  value = aws_eks_cluster.aims.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.aims.endpoint
}

output "eks_cluster_security_group_id" {
  value = aws_eks_cluster.aims.vpc_config[0].cluster_security_group_id
}

output "eks_node_group_name" {
  value = aws_eks_node_group.main.node_group_name
}

output "aws_load_balancer_controller_role_arn" {
  value = aws_iam_role.aws_load_balancer_controller.arn
}

output "kubeconfig_update_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.aims.name} --profile aims-terraform"
}