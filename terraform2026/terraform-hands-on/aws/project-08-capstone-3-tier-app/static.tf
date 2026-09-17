# ── STATIC TIER: private S3 served through CloudFront ─────────────────────────

resource "aws_s3_bucket" "static" {                 # the origin bucket
  bucket = "${var.project}-static-cf-2026"          # globally unique name
  tags   = { Tier = "static" }                      # label
}

resource "aws_s3_bucket_public_access_block" "static" {   # keep it private (CloudFront uses a special identity)
  bucket                    = aws_s3_bucket.static.id     # which bucket
  block_public_acls         = true                        # block public ACLs
  ignore_public_acls        = true                        # ignore public object ACLs
  block_public_policy       = true                        # block public policies
  restrict_public_buckets   = true                        # public policies fail
}

resource "aws_s3_bucket_object" "index" {           # the homepage file
  bucket = aws_s3_bucket.static.id                  # which bucket
  key    = "index.html"                              # the file's path inside the bucket
  content = "Hello from S3 + CloudFront!\n"          # the file's contents (inline, so it's all in Terraform)
  content_type = "text/html"                         # how browsers should treat it
}

resource "aws_cloudfront_origin_access_control" "oac" {   # the special identity CloudFront uses to read private S3
  name                        = "static-s3-oac"        # required: a unique name for the OAC
  origin_access_control_origin_type = "s3"           # the origin is S3
  signing_behavior = "always"                         # sign every request
  signing_protocol = "sigv4"                          # the signing algorithm
}

resource "aws_s3_bucket_policy" "static" {          # allow ONLY CloudFront's OAC identity to read the bucket
  bucket = aws_s3_bucket.static.id                  # which bucket
  policy = jsonencode({                              # build the JSON policy from a Terraform object
    Version = "2012-10-17"                           # the policy document version
    Statement = [{                                    # one statement
      Sid       = "CloudFrontReadOnly"               # an ID for this statement
      Effect    = "Allow"                             # allow
      Principal = { Service = "cloudfront.amazonaws.com" }   # who: the CloudFront service
      Action    = "s3:GetObject"                      # what: read objects
      Resource  = "${aws_s3_bucket.static.arn}/*"    # which objects: everything in this bucket
      Condition = {                                   # with this condition:
        StringEquals = {                              # a string-equality check
          "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"   # must come from our own distributions
        }
      }
    }]
  })
}

data "aws_caller_identity" "current" {              # data block: read our own AWS account ID
  # (no attributes needed — it returns the account that the provider is logged in as)
}

resource "aws_cloudfront_distribution" "static" {   # the distribution: the global CDN
  enabled             = true                         # turn it on
  default_root_object = "index.html"                # "/" serves this file
  price_class         = "PriceClass_100"             # serve only from the US/EU (cheapest)

  origin {                                             # the origin: where content comes from
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name   # the bucket's regional endpoint
    origin_id                = "static-s3"            # a local ID for this origin
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id   # use the OAC identity to read it
  }

  default_cache_behavior {                             # how to treat a request that matches no specific behavior
    target_origin_id = "static-s3"                     # send it to this origin
    viewer_protocol_policy = "redirect-to-https"       # force HTTPS
    allowed_methods        = ["GET", "HEAD"]           # only these HTTP methods
    cached_methods         = ["GET", "HEAD"]           # cache these
    compress               = true                       # gzip text when possible
  }

  restrictions {                                       # request restrictions
    geo_restriction {                                  # geographic blocking
      restriction_type = "none"                        # allow the whole world
    }
  }

  viewer_certificate { cloudfront_default_certificate = true }   # use CloudFront's free certificate

  tags = { Tier = "static" }                           # label
}
