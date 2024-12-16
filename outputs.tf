output "application_url" {
  description = "The URL of the Flask Echo application"
  value       = "http://${module.flask-echo.alb_dns_name}"
} 