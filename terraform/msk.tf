# ------------------------------------------------------------
# Amazon MSK Provisioned - Variables
# ------------------------------------------------------------

variable "msk_cluster_name" {
  description = "Amazon MSK cluster name"
  type        = string
  default     = "aims-dev-msk"
}

variable "msk_kafka_version" {
  description = "Apache Kafka version for Amazon MSK"
  type        = string
  default     = "3.9.x"
}

variable "msk_broker_instance_type" {
  description = "Amazon MSK broker instance type"
  type        = string
  default     = "kafka.t3.small"
}

variable "msk_number_of_broker_nodes" {
  description = "Total number of MSK broker nodes"
  type        = number
  default     = 2
}

variable "msk_ebs_volume_size" {
  description = "EBS volume size in GiB for each broker"
  type        = number
  default     = 100
}

variable "msk_private_subnet_names" {
  description = "Private subnet names for Amazon MSK brokers"
  type        = list(string)

  default = [
    "aims-vpc-subnet-private1-ap-northeast-2a",
    "aims-vpc-subnet-private2-ap-northeast-2b"
  ]
}

# ------------------------------------------------------------
# MSK Private Subnets
# ------------------------------------------------------------

data "aws_subnets" "msk_private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = var.msk_private_subnet_names
  }
}

# ------------------------------------------------------------
# MSK Broker Logs
# ------------------------------------------------------------

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.msk_cluster_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${var.msk_cluster_name}-logs"
  })
}

# ------------------------------------------------------------
# MSK Provisioned Cluster
# kafka.t3.small x 2 brokers
# 2 private subnets
# IAM authentication
# ------------------------------------------------------------

resource "aws_msk_cluster" "aims" {
  cluster_name           = var.msk_cluster_name
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = var.msk_number_of_broker_nodes

  broker_node_group_info {
    instance_type  = var.msk_broker_instance_type
    client_subnets = data.aws_subnets.msk_private.ids

    security_groups = [
      aws_security_group.msk.id
    ]

    storage_info {
      ebs_storage_info {
        volume_size = var.msk_ebs_volume_size
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  enhanced_monitoring = "DEFAULT"

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = var.msk_cluster_name
  })

  depends_on = [
    aws_vpc_security_group_ingress_rule.msk_from_eks_9098
  ]
}

# ------------------------------------------------------------
# Kafka Topics
#
# consumer_count는 문서화용 값
# 실제 Consumer 개수는 Kubernetes Deployment replicas와
# Kafka Consumer Group 설정에서 관리
# ------------------------------------------------------------

locals {
  msk_topics = {
    "factory.manufacturing.raw" = {
      partitions     = 2
      consumer_count = 6
      role           = "원천 제조 이벤트 수집"
    }

    "factory.manufacturing.analysis" = {
      partitions     = 2
      consumer_count = 2
      role           = "AI/Rule 기반 분석 결과 전달"
    }

    "factory.manufacturing.alert" = {
      partitions     = 2
      consumer_count = 1
      role           = "위험 이벤트 및 긴급 알림 전달"
    }

    "factory.manufacturing.equipment" = {
      partitions     = 2
      consumer_count = 1
      role           = "설비 상태 및 가동률 계산 결과 전달"
    }

    "quality.inspection.drive_detail" = {
      partitions     = 1
      consumer_count = 1
      role           = "운전자 상세 데이터 전달"
    }

    "quality.inspection.status_detail" = {
      partitions     = 1
      consumer_count = 1
      role           = "상태 상세 데이터 전달"
    }

    "quality.inspection.process" = {
      partitions     = 1
      consumer_count = 1
      role           = "각 검사 단계 데이터 전달"
    }

    "quality.inspection.risk_history" = {
      partitions     = 1
      consumer_count = 1
      role           = "리스크 이력 전달"
    }

    "quality.inspection.risk_trend" = {
      partitions     = 1
      consumer_count = 1
      role           = "리스크 분석 결과 전달"
    }

    "quality.inspection.summary" = {
      partitions     = 1
      consumer_count = 1
      role           = "검사 요약 데이터 전달"
    }
  }
}

# ------------------------------------------------------------
# Kafka Topic Resources
# Replication Factor: 2
# Minimum In-Sync Replicas: 1
# ------------------------------------------------------------

resource "aws_msk_topic" "topics" {
  for_each = local.msk_topics

  cluster_arn        = aws_msk_cluster.aims.arn
  name               = each.key
  partition_count    = each.value.partitions
  replication_factor = 2

  configs = jsonencode({
    "cleanup.policy"      = "delete"
    "min.insync.replicas" = "1"
  })
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------

output "msk_cluster" {
  description = "AIMS Amazon MSK cluster information"

  value = {
    name                       = aws_msk_cluster.aims.cluster_name
    arn                        = aws_msk_cluster.aims.arn
    kafka_version              = aws_msk_cluster.aims.kafka_version
    broker_instance_type       = var.msk_broker_instance_type
    broker_count               = var.msk_number_of_broker_nodes
    bootstrap_brokers_sasl_iam = aws_msk_cluster.aims.bootstrap_brokers_sasl_iam
    security_group_id          = aws_security_group.msk.id
    subnet_ids                 = data.aws_subnets.msk_private.ids

    topics = {
      for name, topic in aws_msk_topic.topics : name => {
        arn                = topic.arn
        partition_count    = local.msk_topics[name].partitions
        replication_factor = 2
        consumer_count     = local.msk_topics[name].consumer_count
        role               = local.msk_topics[name].role
      }
    }
  }
}

output "msk_cluster_arn" {
  description = "Amazon MSK cluster ARN"
  value       = aws_msk_cluster.aims.arn
}

output "msk_bootstrap_brokers_sasl_iam" {
  description = "Amazon MSK IAM bootstrap brokers"
  value       = aws_msk_cluster.aims.bootstrap_brokers_sasl_iam
}