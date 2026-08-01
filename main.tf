resource "aws_s3_bucket" "origin" {
  bucket_prefix = "apt-registry-"
}

resource "aws_s3_bucket_public_access_block" "origin" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "ca_bundle" {
  bucket = aws_s3_bucket.origin.id
  key    = "ca/root-ca.pem"
  source = "certificates/root-ca.pem"
}

data "aws_iam_policy_document" "origin_read" {
  # trust store CA bundle import reads carry the trust store ARN
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.origin.arn}/ca/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_trust_store.root_ca.arn]
    }
  }

  # distribution origin fetches carry the distribution ARN
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.origin.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.repository.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "origin_read" {
  bucket = aws_s3_bucket.origin.id
  policy = data.aws_iam_policy_document.origin_read.json
}

resource "aws_cloudfront_origin_access_control" "origin" {
  name                              = "apt-registry-origin-access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_trust_store" "root_ca" {
  name = "apt-registry-root-ca"

  ca_certificates_bundle_source {
    ca_certificates_bundle_s3_location {
      bucket = aws_s3_bucket.origin.id
      key    = aws_s3_object.ca_bundle.key
      region = "us-east-1"
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "repository" {
  enabled    = true
  comment    = "apt-registry"
  web_acl_id = aws_wafv2_web_acl.repository.arn

  origin {
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id                = "apt-registry-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.origin.id
  }

  default_cache_behavior {
    target_origin_id       = "apt-registry-origin"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "https-only"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  viewer_mtls_config {
    mode = "required"

    trust_store_config {
      trust_store_id = aws_cloudfront_trust_store.root_ca.id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_wafv2_ip_set" "allowlist" {
  name               = "apt-registry-allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"

  # intentionally empty: the allow layer exists but is not blocking yet
  addresses = []
}

resource "aws_wafv2_web_acl" "repository" {
  name  = "apt-registry-web-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "allowlist"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.allowlist.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "apt-registry-allowlist"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "apt-registry-web-acl"
    sampled_requests_enabled   = false
  }
}
