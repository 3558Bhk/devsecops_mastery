# ============================================================================
#  CloudFront — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_s3_bucket" "web" {                 # the origin bucket
  bucket = "cf-origin-lab-2026"                  # the GLOBAL name
}

resource "aws_s3_bucket_public_access_block" "web" {   # private (CloudFront's OAC is the only reader)
  bucket                  = aws_s3_bucket.web.id   # which bucket
  block_public_acls       = true                     # no public ACLs
  block_public_policy     = true                     # no public policies
  ignore_public_acls      = true                     # strip public ACLs
  restrict_public_buckets = true                     # public only if explicitly asked
}

resource "aws_s3_object" "index" {               # one object so there's something to serve
  bucket = aws_s3_bucket.web.id                 # which bucket
  key    = "index.html"                         # the object's path
  content = "<h1>Hello from CloudFront + private S3</h1>"   # the content
  content_type = "text/html"                    # the content type
}

resource "aws_cloudfront_origin_access_control" "web" {   # the OAC object
  name                              = "cf-origin-lab-oac"   # the OAC's name
  origin_access_control_origin_type = "s3"                  # for an S3 origin
  signing_behavior                  = "no-override"                 # don't force a different signing behaviour
  signing_protocol                  = "sigv4"               # sign with SigV4
  description = "OAC for the lab origin"                  # a note
}

resource "aws_s3_bucket_policy" "oac" {         # the bucket side of the handshake
  bucket = aws_s3_bucket.web.id                 # which bucket

  policy = jsonencode({                          # the policy JSON
    Version = "2012-10-17"                        # the version
    Statement = [{                                 # one statement
      Sid       = "AllowCloudFrontOAC"            # an id
      Effect    = "Allow"                         # allow
      Principal = {                               # by the OAC (not by anyone!)
        Service   = "cloudfront.amazonaws.com"    # the CloudFront service
        AWS       = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Control ${aws_cloudfront_origin_access_control.web.id}"   # this specific OAC
      }
      Action   = "s3:GetObject"                   # reading objects
      Resource = "${aws_s3_bucket.web.arn}/*"    # in this bucket
      Condition = {                                # ...and only via this distribution
        StringEquals = {                            # match on the header
          "cloudfront:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.web.id}"   # this distribution
        }
      }
    }]
  })
}

data "aws_caller_identity" "current" {           # data block: the account id (for the policy)
  # no arguments — the account the provider is logged in as
}

resource "aws_cloudfront_distribution" "web" {   # the distribution
  enabled             = true                       # live immediately
  default_root_object = "index.html"               # what "/" serves

  origin {                                          # the origin (S3, via the OAC)
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name   # the S3 domain
    origin_id                = "s3-origin"         # an id for the origin (used by the behavior)
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id   # the OAC link
  }

  default_cache_behavior {                           # the default behavior: what to cache and how
    target_origin_id       = "s3-origin"             # which origin
    viewer_protocol_policy = "redirect-to-https"     # force HTTPS for viewers
    allowed_methods        = ["GET", "HEAD"]         # only read methods through this behavior
    cached_methods         = ["GET", "HEAD"]         # cache these
    compress               = true                    # gzip on the fly


    # the cache policy default (PriceClass all regions + standard headers) is fine here
  }

  restrictions {                                      # the geographic + protocol fence
    geo_restriction {                                 # who may use it
      restriction_type = "none"                        # no geo restriction (or "blacklist"/"whitelist")
    }
  }

  viewer_certificate {                                # the TLS cert for the edge
    cloudfront_default_certificate = true              # the free *.cloudfront.net cert
  }

  price_class = "PriceClass_100"                       # all edge locations (100) vs 200 (cheap, no Asia)
}
