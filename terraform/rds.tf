# ------------------------------------------------------------
# RDS Private Subnet Data
# ------------------------------------------------------------

data "aws_subnets" "rds_private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = var.private_db_subnet_names
  }
}

# ------------------------------------------------------------
# RDS DB Subnet Group
# ------------------------------------------------------------

resource "aws_db_subnet_group" "rds" {
  name        = "${local.name_prefix}-rds-subnet-group"
  description = "DB subnet group for AIMS MySQL RDS"
  subnet_ids  = data.aws_subnets.rds_private.ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
  })
}

# ------------------------------------------------------------
# RDS MySQL Parameter Group
# ------------------------------------------------------------

resource "aws_db_parameter_group" "mysql" {
  name        = "${local.name_prefix}-mysql84-parameter-group"
  family      = "mysql8.4"
  description = "Custom parameter group for AIMS MySQL RDS"

  parameter {
    name         = "wait_timeout"
    value        = "5"
    apply_method = "immediate"
  }

  parameter {
    name         = "interactive_timeout"
    value        = "5"
    apply_method = "immediate"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql84-parameter-group"
  })
}

# ------------------------------------------------------------
# Single RDS MySQL Instance
# sampledb는 RDS 생성 시 initial database로 생성
# maindb는 생성 후 SQL로 추가 생성
# ------------------------------------------------------------

resource "aws_db_instance" "mysql" {
  identifier = var.rds_identifier

  engine         = "mysql"
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.rds_initial_db_name
  username = var.rds_master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # 사용자 정의 파라미터 그룹 적용
  parameter_group_name = aws_db_parameter_group.mysql.name

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 1
  copy_tags_to_snapshot   = true
  deletion_protection     = false
  skip_final_snapshot     = true

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(local.common_tags, {
    Name        = var.rds_identifier
    Description = "AIMS single MySQL RDS instance for sampledb and maindb"
  })
}