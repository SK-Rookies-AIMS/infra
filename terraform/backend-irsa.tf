# ------------------------------------------------------------
# Backend S3 IRSA IAM Role
# ------------------------------------------------------------

data "aws_iam_policy_document" "backend_s3_assume_role" {
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
      values   = ["system:serviceaccount:aims-project:backend"]
    }
  }
}

resource "aws_iam_role" "backend_s3" {
  name               = "${var.eks_cluster_name}-backend-s3-role"
  assume_role_policy = data.aws_iam_policy_document.backend_s3_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.eks_cluster_name}-backend-s3-role"
  })
}

# ------------------------------------------------------------
# Backend Event Image S3 IAM Policy
# ------------------------------------------------------------

resource "aws_iam_policy" "backend_s3" {
  name        = "${var.eks_cluster_name}-backend-s3-policy"
  description = "IAM Policy for Backend to read and write event images in S3"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]

        Resource = [
          "arn:aws:s3:::event-image-858507113889-ap-northeast-2-an/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backend_s3" {
  role       = aws_iam_role.backend_s3.name
  policy_arn = aws_iam_policy.backend_s3.arn
}

output "backend_s3_role_arn" {
  value       = aws_iam_role.backend_s3.arn
  description = "The ARN of the IAM role for Backend S3 event image access"
}
