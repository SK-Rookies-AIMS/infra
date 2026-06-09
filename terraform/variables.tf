variable "project" {
  default = "aims"
}

variable "env" {
  default = "dev"
}

variable "region" {
  default = "ap-northeast-2"
}

variable "vpc_cidr" {
  default = "10.10.0.0/16"
}

variable "my_ip" {
  description = "Your public IP for Bastion SSH access"
  type        = string
}

variable "vpc_id" {
  description = "Existing AIMS VPC ID"
  type        = string
  default     = "vpc-0742bb87c02e3ae5f"
}

variable "db_port" {
  description = "RDS DB port. MySQL = 3306, PostgreSQL = 5432"
  type        = number
  default     = 3306
}

variable "private_db_subnet_names" {
  description = "Private subnet names for RDS DB subnet group"
  type        = list(string)

  default = [
    "aims-vpc-subnet-private1-ap-northeast-2a",
    "aims-vpc-subnet-private2-ap-northeast-2b"
  ]
}

variable "rds_identifier" {
  description = "RDS instance identifier"
  type        = string
  default     = "aims-dev-mysql"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage size in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "RDS autoscaling max storage size in GB"
  type        = number
  default     = 100
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "rds_initial_db_name" {
  description = "Initial database created with RDS instance"
  type        = string
  default     = "sampledb"
}