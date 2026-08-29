output "repository_url" {
  description = "Push target for the node-monitor image"
  value       = aws_ecr_repository.node_monitor.repository_url
}

output "registry_id" {
  description = "AWS account ID that owns the registry"
  value       = data.aws_caller_identity.current.account_id
}

output "login_command" {
  description = "Authenticate a local Docker client against this registry"
  value       = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}
