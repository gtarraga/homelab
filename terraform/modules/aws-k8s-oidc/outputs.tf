output "oidc_bucket_name" {
  value = aws_s3_bucket.oidc.bucket
}

output "oidc_issuer_url" {
  value = local.issuer_url
}

output "eso_parameter_store_reader_role_arn" {
  value = aws_iam_role.eso.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.k8s.arn
}