# Create IAM role for Lambda
resource "aws_iam_role" "lambda_datadog_forwarder" {
  name = "${var.name_prefix}-datadog-forwarder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Add permissions for Lambda to read from CloudWatch Logs
resource "aws_iam_role_policy" "lambda_datadog_forwarder" {
  name = "${var.name_prefix}-datadog-forwarder-policy"
  role = aws_iam_role.lambda_datadog_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Create Lambda deployment package
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/lambda/main.py"
  output_path = "${path.module}/lambda/function.zip"
}

# Create Lambda function for Datadog forwarding
resource "aws_lambda_function" "datadog_forwarder" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = "${var.name_prefix}-datadog-forwarder"
  role            = aws_iam_role.lambda_datadog_forwarder.arn
  handler         = "main.lambda_handler"
  runtime         = "python3.8"
  timeout         = 120
  memory_size     = 1024

  environment {
    variables = {
      DD_API_KEY = var.datadog_api_key
      DD_SITE    = var.datadog_site
      DD_TAGS    = var.datadog_tags
    }
  }

  source_code_hash = data.archive_file.lambda_package.output_base64sha256
}

# Create CloudWatch Log subscriptions for each log group
resource "aws_cloudwatch_log_subscription_filter" "datadog_logs" {
  for_each = toset(var.log_group_names)

  name            = "${var.name_prefix}-datadog-logs-${replace(each.value, "/", "-")}"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = aws_lambda_function.datadog_forwarder.arn
}

# Add Lambda permissions for each log group
resource "aws_lambda_permission" "cloudwatch_logs" {
  for_each = toset(var.log_group_names)

  statement_id  = "AllowCloudWatch${replace(each.value, "/", "_")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.datadog_forwarder.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:${each.value}:*"
} 