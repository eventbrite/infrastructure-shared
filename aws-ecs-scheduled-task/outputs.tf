output "execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = module.task_definition.execution_role_arn
}

output "image_parameter_arns" {
  description = "SSM image parameter ARNs keyed by application container name."
  value       = module.task_definition.image_parameter_arns
}

output "task_role_arn" {
  description = "ECS task role ARN."
  value       = module.task_definition.task_role_arn
}
