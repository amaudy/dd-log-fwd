variable "name_prefix" {
  description = "Prefix to use for resource names"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "datadog_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Datadog site (e.g., datadoghq.com)"
  type        = string
  default     = "datadoghq.com"
}

variable "datadog_tags" {
  description = "Tags to add to all logs sent to Datadog"
  type        = string
  default     = ""
}

variable "log_group_names" {
  description = "List of CloudWatch Log Group names to forward to Datadog"
  type        = list(string)
} 