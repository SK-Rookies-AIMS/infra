# ------------------------------------------------------------
# Assembly Service MSK SASL/IAM IRSA IAM Role
# ------------------------------------------------------------

data "aws_iam_policy_document" "assembly_msk_assume_role" {
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
      values   = ["system:serviceaccount:aims-project:assembly-service"]
    }
  }
}

resource "aws_iam_role" "assembly_msk" {
  name               = "aims-dev-assembly-service-role"
  assume_role_policy = data.aws_iam_policy_document.assembly_msk_assume_role.json

  tags = merge(local.common_tags, {
    Name = "aims-dev-assembly-service-role"
  })
}

# MSK IAM Policy for Assembly Service
resource "aws_iam_policy" "assembly_msk" {
  name        = "aims-dev-assembly-service-policy"
  description = "IAM Policy for Assembly Service to connect, read, and write from MSK cluster using SASL/IAM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "assembly_msk" {
  role       = aws_iam_role.assembly_msk.name
  policy_arn = aws_iam_policy.assembly_msk.arn
}

output "assembly_msk_role_arn" {
  value       = aws_iam_role.assembly_msk.arn
  description = "The ARN of the IAM role for Assembly Service MSK"
}
