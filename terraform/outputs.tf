output "security_group_ids" {
  description = "AIMS security group IDs"

  value = {
    alb        = aws_security_group.alb.id
    bastion    = aws_security_group.bastion.id
    eks_nodes  = aws_security_group.eks_nodes.id
    rds        = aws_security_group.rds.id
    msk        = aws_security_group.msk.id
    redis      = aws_security_group.redis.id
    opensearch = aws_security_group.opensearch.id
  }
}

output "rds_instance" {
  description = "AIMS RDS instance connection information"

  value = {
    identifier = aws_db_instance.mysql.identifier
    address    = aws_db_instance.mysql.address
    endpoint   = aws_db_instance.mysql.endpoint
    port       = aws_db_instance.mysql.port
    username   = aws_db_instance.mysql.username
    databases  = ["sampledb", "maindb"]
  }
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS master user password"
  value       = try(aws_db_instance.mysql.master_user_secret[0].secret_arn, null)
}