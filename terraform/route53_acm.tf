# ------------------------------------------------------------
# Route 53 + ACM Variables
# ------------------------------------------------------------

variable "enable_domain" {
  description = "Enable Route53 and ACM resources"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Main domain name"
  type        = string
  default     = "aims-factory.com"
}

variable "route53_record_name" {
  description = "A record name. Use aims-factory.com or api.aims-factory.com"
  type        = string
  default     = "aims-factory.com"
}

variable "alb_dns_name" {
  description = "ALB DNS name. Fill after Kubernetes Ingress creates ALB."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "ALB canonical hosted zone ID. Fill after ALB is created."
  type        = string
  default     = ""
}

# ------------------------------------------------------------
# Existing Hosted Zone
# Route 53에서 도메인 구매 시 Hosted Zone은 자동 생성됨
# ------------------------------------------------------------

data "aws_route53_zone" "main" {
  count        = var.enable_domain ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

# ------------------------------------------------------------
# ACM Certificate
# ALB가 ap-northeast-2에 있으므로 ACM도 ap-northeast-2에 발급
# ------------------------------------------------------------

resource "aws_acm_certificate" "main" {
  count = var.enable_domain ? 1 : 0

  domain_name = var.domain_name

  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.env}-acm-${var.domain_name}"
  })
}

locals {
  acm_validation_records = var.enable_domain ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
}

resource "aws_route53_record" "acm_validation" {
  for_each = local.acm_validation_records

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60

  records = [
    each.value.record
  ]

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count = var.enable_domain ? 1 : 0

  certificate_arn = aws_acm_certificate.main[0].arn

  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation : record.fqdn
  ]
}

# ------------------------------------------------------------
# Route53 A Alias Record
# ALB가 아직 없으면 생성되지 않음
# Ingress 생성 후 alb_dns_name, alb_zone_id 값을 넣고 다시 apply
# ------------------------------------------------------------

resource "aws_route53_record" "app_alias" {
  count = var.enable_domain && var.alb_dns_name != "" && var.alb_zone_id != "" ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.route53_record_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

output "route53_zone_id" {
  value = var.enable_domain ? data.aws_route53_zone.main[0].zone_id : null
}

output "acm_certificate_arn" {
  value = var.enable_domain ? aws_acm_certificate_validation.main[0].certificate_arn : null
}