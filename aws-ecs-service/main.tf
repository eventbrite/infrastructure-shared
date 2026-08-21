locals {
  name = "${var.service}-${var.environment}"
  cluster_name = element(
    split("/", var.cluster_arn),
    length(split("/", var.cluster_arn)) - 1,
  )
}

data "aws_caller_identity" "current" {}

module "task_definition" {
  source = "../_/aws-ecs-task-definition"

  account_id                             = coalesce(var.account_id, data.aws_caller_identity.current.account_id)
  application_name                       = var.service
  containers                             = var.containers
  cpu                                    = var.task_cpu
  datadog_agent_cpu                      = var.datadog_agent_cpu
  datadog_agent_environment              = var.datadog_agent_environment
  datadog_agent_image                    = var.datadog_agent_image
  datadog_agent_memory_reservation       = var.datadog_agent_memory_reservation
  datadog_api_key_secret_arn             = var.datadog_api_key_secret_arn
  datadog_api_key_secret_name            = var.datadog_api_key_secret_name
  datadog_apm_enabled                    = var.datadog_apm_enabled
  datadog_enabled                        = var.datadog_enabled
  environment                            = var.environment
  execution_pull_through_repository_arns = var.execution_pull_through_repository_arns
  execution_secret_arns                  = var.execution_secret_arns
  existing_execution_role_arn            = var.existing_execution_role_arn
  existing_task_role_arn                 = var.existing_task_role_arn
  firelens_cpu                           = var.firelens_cpu
  firelens_image                         = var.firelens_image
  firelens_memory_reservation            = var.firelens_memory_reservation
  memory                                 = var.task_memory
  name                                   = local.name
  region                                 = var.region
  tags                                   = var.tags
  task_role_policy_json                  = var.task_role_policy_json
  volumes                                = var.volumes
}

resource "aws_ecs_service" "this" {
  cluster                           = var.cluster_arn
  desired_count                     = var.autoscaling != null ? var.autoscaling.min_capacity : var.desired_count
  health_check_grace_period_seconds = var.health_check_grace_period_seconds
  launch_type                       = "FARGATE"
  name                              = local.name
  propagate_tags                    = "TASK_DEFINITION"
  tags                              = var.tags
  task_definition                   = module.task_definition.task_definition_arn

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker.enable
    rollback = var.deployment_circuit_breaker.rollback
  }

  dynamic "load_balancer" {
    for_each = var.load_balancers

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = var.security_group_ids
    subnets          = var.subnets
  }

  lifecycle {
    # ECS or the autoscaler owns the live count after the initial deployment.
    # Deployment automation owns the live task revision.
    ignore_changes = [desired_count, task_definition]

    precondition {
      condition     = (var.autoscaling == null) != (var.desired_count == null)
      error_message = "Set exactly one of autoscaling or desired_count."
    }
  }

  # Secrets and task-role policies must exist before ECS can launch the task.
  depends_on = [module.task_definition]
}

resource "aws_appautoscaling_target" "this" {
  count = var.autoscaling == null ? 0 : 1

  max_capacity       = var.autoscaling.max_capacity
  min_capacity       = var.autoscaling.min_capacity
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  lifecycle {
    # Terraform seeds the floor; operators and the autoscaler own it afterward.
    ignore_changes = [min_capacity]
  }
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.autoscaling == null ? 0 : 1

  name               = "${local.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.cpu.target_value
    scale_out_cooldown = var.autoscaling.cpu.scale_out_cooldown
    scale_in_cooldown  = var.autoscaling.cpu.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
