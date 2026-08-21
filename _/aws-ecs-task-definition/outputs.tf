output "execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = local.execution_role_arn
}

output "family" {
  description = "Task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "image_parameter_arns" {
  description = "SSM image parameter ARNs keyed by application container name."
  value       = { for name, parameter in aws_ssm_parameter.image : name => parameter.arn }
}

output "task_definition_arn" {
  description = "ARN of the Terraform-managed task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_arn_without_revision" {
  description = "Task definition family ARN without a revision."
  value       = aws_ecs_task_definition.this.arn_without_revision
}

output "task_role_arn" {
  description = "ECS task role ARN."
  value       = local.task_role_arn
}
