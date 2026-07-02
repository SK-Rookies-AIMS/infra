# ------------------------------------------------------------
# Logstash MSK SASL/IAM IRSA IAM Role
# ------------------------------------------------------------

data "aws_iam_policy_document" "logstash_msk_assume_role" {
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
      values   = ["system:serviceaccount:platform:logstash-msk"]
    }
  }
}

resource "aws_iam_role" "logstash_msk" {
  name               = "${var.eks_cluster_name}-logstash-msk-role"
  assume_role_policy = data.aws_iam_policy_document.logstash_msk_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-logstash-msk-role"
  })
}

# MSK IAM Policy
resource "aws_iam_policy" "logstash_msk" {
  name        = "${var.eks_cluster_name}-logstash-msk-policy"
  description = "IAM Policy for Logstash to connect and read from MSK cluster using SASL/IAM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "logstash_msk" {
  role       = aws_iam_role.logstash_msk.name
  policy_arn = aws_iam_policy.logstash_msk.arn
}

output "logstash_msk_role_arn" {
  value       = aws_iam_role.logstash_msk.arn
  description = "The ARN of the IAM role for Logstash MSK"
}
