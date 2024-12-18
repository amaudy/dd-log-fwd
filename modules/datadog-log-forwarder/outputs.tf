output "lambda_function_arn" {
  description = "ARN of the created Lambda function"
  value       = aws_lambda_function.datadog_forwarder.arn
}

output "lambda_function_name" {
  description = "Name of the created Lambda function"
  value       = aws_lambda_function.datadog_forwarder.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_datadog_forwarder.arn
} 