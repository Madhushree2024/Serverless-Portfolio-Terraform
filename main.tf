# 1. THE STORAGE (S3 BUCKET)
resource "aws_s3_bucket" "my_portfolio" {
  bucket = "madhushree-portfolio-site-2026" 

  tags = {
    Name        = "Portfolio Bucket"
    Environment = "Dev"
  }
}

# 2. STATIC WEBSITE CONFIGURATION
resource "aws_s3_bucket_website_configuration" "portfolio_config" {
  bucket = aws_s3_bucket.my_portfolio.id

  index_document {
    suffix = "index.html"
  }
}

# 3. VERSIONING
resource "aws_s3_bucket_versioning" "portfolio_versioning" {
  bucket = aws_s3_bucket.my_portfolio.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 4. PUBLIC ACCESS SETTINGS
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.my_portfolio.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls       = false
  restrict_public_buckets = false
}

# 5. BUCKET POLICY
resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.my_portfolio.id
  depends_on = [aws_s3_bucket_public_access_block.public_access]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.my_portfolio.arn}/*"
      },
    ]
  })
}

# 6. AUTOMATIC FILE UPLOADS
resource "aws_s3_object" "upload_index" {
  bucket       = aws_s3_bucket.my_portfolio.id
  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
  etag         = filemd5("index.html")
}

resource "aws_s3_object" "upload_favicon" {
  bucket       = aws_s3_bucket.my_portfolio.id
  key          = "favicon.ico"
  source       = "favicon.ico"
  content_type = "image/x-icon"
}

# 7. CLOUDFRONT CDN
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.my_portfolio.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.my_portfolio.bucket}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.my_portfolio.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# 8. DYNAMODB (Visitor Tracking)
resource "aws_dynamodb_table" "visitor_count" {
  name         = "visitor_counter_v2"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# PRO-UPDATE: Initial Record with Lifecycle Protection
resource "aws_dynamodb_table_item" "initial_count" {
  table_name = aws_dynamodb_table.visitor_count.name
  hash_key   = aws_dynamodb_table.visitor_count.hash_key

  item = jsonencode({
    id    = { S = "visitors" }
    count = { N = "0" }
  })

  # This prevents the count from resetting to 0 every time you deploy!
  lifecycle {
    ignore_changes = [item]
  }
}

# 9. CLOUDWATCH LOGS (Pre-create the group)
resource "aws_cloudwatch_log_group" "lambda_log" {
  name              = "/aws/lambda/visitor_counter_func_v2"
  retention_in_days = 7
}

# 10. LAMBDA & IAM
resource "aws_iam_role" "lambda_role" {
  name = "portfolio_lambda_role_v2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# PRO-UPDATE: Unified permissions for DB and Logging
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_combined_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.visitor_count.arn
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_log.arn}:*"
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  filename         = "lambda_function.zip"
  function_name    = "visitor_counter_func_v2"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# 11. API GATEWAY
resource "aws_apigatewayv2_api" "visitor_api" {
  name          = "visitor_counter_api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.visitor_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.visitor_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.visitor_counter.invoke_arn
}

resource "aws_apigatewayv2_route" "api_route" {
  api_id    = aws_apigatewayv2_api.visitor_api.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_api.execution_arn}/*/*"
}

# 12. OUTPUTS
output "cloudfront_url" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "api_url" {
  value = "${aws_apigatewayv2_api.visitor_api.api_endpoint}/count"
}