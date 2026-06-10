# ------------------------------------------------------------
# ElastiCache Redis Variables
# ------------------------------------------------------------

variable "redis_subnet_names" {
  description = "Private subnet names for ElastiCache Redis subnet group"
  type        = list(string)

  default = [
    "aims-vpc-subnet-private1-ap-northeast-2a",
    "aims-vpc-subnet-private2-ap-northeast-2b"
  ]
}

variable "redis_replication_group_id" {
  description = "ElastiCache Redis replication group ID"
  type        = string
  default     = "aims-dev-redis"
}

variable "redis_engine_version" {
  description = "Redis OSS engine version"
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t4g.medium"
}

variable "redis_num_cache_clusters" {
  description = "Number of Redis cache nodes. 2 means primary 1 plus replica 1."
  type        = number
  default     = 2
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_allow_bastion_access" {
  description = "Allow Bastion to access Redis for temporary backend development before EKS is ready"
  type        = bool
  default     = true
}

# ------------------------------------------------------------
# ElastiCache Redis Private Subnet Data
# ------------------------------------------------------------

data "aws_subnets" "redis_private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = var.redis_subnet_names
  }
}

# ------------------------------------------------------------
# ElastiCache Redis Subnet Group
# ------------------------------------------------------------

resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.name_prefix}-redis-subnet-group"
  description = "Subnet group for AIMS dev Redis"
  subnet_ids  = data.aws_subnets.redis_private.ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-subnet-group"
  })
}

# ------------------------------------------------------------
# Redis Security Group Rule
# Bastion -> Redis
# EKS가 아직 없을 때 로컬 백엔드 개발자가 SSH 터널로 Redis를 테스트할 수 있도록 허용
# 운영 또는 EKS 전환 이후에는 redis_allow_bastion_access = false 로 변경 권장
# ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "redis_from_bastion_dev" {
  count = var.redis_allow_bastion_access ? 1 : 0

  security_group_id            = aws_security_group.redis.id
  description                  = "Allow Redis from Bastion for temporary backend development"
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
}

# ------------------------------------------------------------
# ElastiCache Redis Replication Group
# cache.t4g.medium x 2 nodes
# Cluster mode disabled, 1 primary + 1 replica
# ------------------------------------------------------------

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = var.redis_replication_group_id
  description          = "AIMS dev Redis cache for backend development"

  engine         = "redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type
  port           = var.redis_port

  num_cache_clusters         = var.redis_num_cache_clusters
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  snapshot_retention_limit = 1
  apply_immediately        = true

  tags = merge(local.common_tags, {
    Name        = var.redis_replication_group_id
    Description = "AIMS Redis OSS single shard cache for backend development"
  })
}

# ------------------------------------------------------------
# ElastiCache Redis Outputs
# ------------------------------------------------------------

output "redis_instance" {
  description = "AIMS Redis connection information"

  value = {
    replication_group_id = aws_elasticache_replication_group.redis.replication_group_id
    primary_endpoint     = aws_elasticache_replication_group.redis.primary_endpoint_address
    reader_endpoint      = aws_elasticache_replication_group.redis.reader_endpoint_address
    port                 = aws_elasticache_replication_group.redis.port
    node_type            = var.redis_node_type
    node_count           = var.redis_num_cache_clusters
    subnet_group         = aws_elasticache_subnet_group.redis.name
    bastion_access       = var.redis_allow_bastion_access
  }
}