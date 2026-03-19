data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  bucket_name = "homelab-k8s-oidc-${data.aws_caller_identity.current.account_id}"
  issuer_url  = "https://${local.bucket_name}.s3.${data.aws_region.current.name}.amazonaws.com"
}

data "tls_certificate" "s3" {
  url        = local.issuer_url
  depends_on = [aws_s3_bucket.oidc]
}

resource "aws_s3_bucket" "oidc" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  block_public_acls = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.oidc.arn}/*"
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "k8s" {
  url             = local.issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.s3.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type = "Federated"
      identifiers = [aws_iam_openid_connect_provider.k8s.arn]
    }
    condition {
      test = "StringEquals"
      variable = "${local.issuer_url}:aud"
      values = ["sts.amazonaws.com"]
    }
    condition {
      test = "StringEquals"
      variable = "${local.issuer_url}:sub"
      values = ["system:serviceaccount:infra:external-secrets"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name = "eso-parameter-store-reader"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json
}

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    sid = "SSMParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/homelab/*",
    ]
  }
  statement {
    sid = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "eso" {
  name = "eso-parameter-store-reader-policy"
  policy = data.aws_iam_policy_document.eso_permissions.json
}

resource "aws_iam_role_policy_attachment" "eso" {
  role = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}