locals {
  name_prefix = "${var.project}-${var.env}"

  common_tags = {
    Project = var.project
    Env     = var.env
    Managed = "terraform"
  }
}

data "aws_vpc" "aims" {
  id = var.vpc_id
}

# ------------------------------------------------------------
# Security Groups
# ------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Security group for Bastion Host"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion-sg"
  })
}

resource "aws_security_group" "eks_nodes" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "Security group for EKS Node Group"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_security_group" "msk" {
  name        = "${local.name_prefix}-msk-sg"
  description = "Security group for MSK Kafka"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-msk-sg"
  })
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-sg"
  })
}

resource "aws_security_group" "opensearch" {
  name        = "${local.name_prefix}-opensearch-sg"
  description = "Security group for OpenSearch"
  vpc_id      = data.aws_vpc.aims.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-opensearch-sg"
  })
}

# ------------------------------------------------------------
# ALB Inbound Rules
# Internet -> ALB
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ------------------------------------------------------------
# Bastion Inbound Rules
# My PC -> Bastion
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow SSH from my IP"
  cidr_ipv4         = var.my_ip
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# ------------------------------------------------------------
# EKS Node Inbound Rules
# ALB -> EKS
# EKS Node -> EKS Node
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "eks_from_alb_http" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow HTTP traffic from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_alb_8080" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow backend traffic from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_alb_3000" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow frontend dev traffic from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_ingress_rule" "eks_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Allow all traffic between EKS nodes"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "-1"
}

# ------------------------------------------------------------
# RDS Inbound Rules
# Bastion -> RDS
# EKS -> RDS
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_from_bastion" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow DB access from Bastion"
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Allow DB access from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

# ------------------------------------------------------------
# MSK Inbound Rules
# EKS -> MSK
# 9098: SASL/IAM Authentication + TLS
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "msk_from_eks_9098" {
  security_group_id            = aws_security_group.msk.id
  description                  = "Allow Kafka IAM authentication from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 9098
  to_port                      = 9098
}

# ------------------------------------------------------------
# Redis Inbound Rules
# EKS -> Redis
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Allow Redis from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}

# ------------------------------------------------------------
# OpenSearch Inbound Rules
# EKS -> OpenSearch
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "opensearch_from_eks" {
  security_group_id            = aws_security_group.opensearch.id
  description                  = "Allow HTTPS from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# ------------------------------------------------------------
# Egress Rules
# 현재는 초안이므로 Outbound 전체 허용
# 추후 보안 강화 단계에서 최소 권한으로 줄이면 됨
# ------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "eks_all" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "msk_all" {
  security_group_id = aws_security_group.msk.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "redis_all" {
  security_group_id = aws_security_group.redis.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "opensearch_all" {
  security_group_id = aws_security_group.opensearch.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}