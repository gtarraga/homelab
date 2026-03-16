data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tfstate_bucket_arn = "arn:aws:s3:::homelab-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

data "aws_iam_policy_document" "github_terraform_permissions" {
  statement {
    sid    = "SSMParameterAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:PutParameter",
      "ssm:DeleteParameter",
    ]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_path_prefix}*"]
  }
  statement {
    sid       = "SSMDescribeParameters"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
  statement {
    sid    = "IAMSelfManage"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
    ]
    resources = [
      aws_iam_openid_connect_provider.github.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.role_name}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.role_name}-policy",
    ]
  }
  statement {
    sid       = "KMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }
  statement {
    sid    = "S3TFStateAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      local.tfstate_bucket_arn,
      "${local.tfstate_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "github_terraform_policy" {
  name   = "${var.role_name}-policy"
  policy = data.aws_iam_policy_document.github_terraform_permissions.json
}

resource "aws_iam_role_policy_attachment" "github_terraform_attach" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}
