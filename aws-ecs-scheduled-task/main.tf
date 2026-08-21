data "aws_caller_identity" "current" {}

locals {
  account_id = coalesce(var.account_id, data.aws_caller_identity.current.account_id)
}

module "task_definition" {
  source = "../_/aws-ecs-task-definition"

  account_id                             = local.account_id
  application_name                       = var.application_name
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
  name                                   = var.name
  region                                 = var.region
  tags                                   = var.tags
  task_role_policy_json                  = var.task_role_policy_json
  volumes                                = var.volumes
}

resource "aws_scheduler_schedule_group" "this" {
  name = coalesce(var.schedule_group_name, var.name)
  tags = var.tags
}

resource "aws_iam_role" "scheduler" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
        ArnEquals = {
          "aws:SourceArn" = aws_scheduler_schedule_group.this.arn
        }
      }
    }]
  })
  name = "${var.name}-scheduler"
  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "run-task"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RunTask"
        Effect = "Allow"
        Action = "ecs:RunTask"
        Resource = format(
          "arn:aws:ecs:%s:%s:task-definition/%s:*",
          var.region,
          local.account_id,
          module.task_definition.family,
        )
        Condition = {
          ArnEquals = {
            "ecs:cluster" = var.cluster_arn
          }
        }
      },
      {
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = distinct([module.task_definition.execution_role_arn, module.task_definition.task_role_arn])
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
    ]
  })
  role = aws_iam_role.scheduler.name
}

resource "aws_scheduler_schedule" "this" {
  for_each = var.schedules

  description                  = each.value.description
  group_name                   = aws_scheduler_schedule_group.this.name
  name                         = coalesce(each.value.name, each.key)
  schedule_expression          = each.value.expression
  schedule_expression_timezone = each.value.timezone
  state                        = each.value.enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn = var.cluster_arn
    input = length(each.value.command_overrides) > 0 ? jsonencode({
      containerOverrides = [
        for container_name, command in each.value.command_overrides : {
          name    = container_name
          command = command
        }
      ]
    }) : null
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      launch_type         = "FARGATE"
      propagate_tags      = "TASK_DEFINITION"
      task_definition_arn = module.task_definition.task_definition_arn_without_revision

      network_configuration {
        assign_public_ip = false
        security_groups  = var.security_group_ids
        subnets          = var.subnets
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = each.value.maximum_event_age
      maximum_retry_attempts       = each.value.maximum_retry_count
    }
  }
}
