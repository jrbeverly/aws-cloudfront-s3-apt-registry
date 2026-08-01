output "cloudfront_domain" {
  value = aws_cloudfront_distribution.repository.domain_name
}

output "bucket_name" {
  value = aws_s3_bucket.origin.id
}
