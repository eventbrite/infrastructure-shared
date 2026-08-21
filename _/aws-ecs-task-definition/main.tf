locals {
  datadog_secret_arn = var.datadog_api_key_secret_arn != null ? var.datadog_api_key_secret_arn : try(data.aws_secretsmanager_secret.datadog[0].arn, null)

  execution_secret_arns = distinct(concat(
    var.execution_secret_arns,
    [
      for secret in flatten([
        for container in values(var.containers) : container.secrets
      ]) : regex("^arn:[^:]+:secretsmanager:[^:]+:[^:]+:secret:[^:]+", secret.value_from)
      if can(regex("^arn:[^:]+:secretsmanager:[^:]+:[^:]+:secret:[^:]+", secret.value_from))
    ],
    var.datadog_enabled ? [local.datadog_secret_arn] : [],
  ))

  execution_ssm_parameter_arns = distinct([
    for secret in flatten([
      for container in values(var.containers) : container.secrets
    ]) : regex("^arn:[^:]+:ssm:[^:]+:[^:]+:parameter/.+", secret.value_from)
    if can(regex("^arn:[^:]+:ssm:[^:]+:[^:]+:parameter/.+", secret.value_from))
  ])

  assume_ecs_tasks = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:ecs:${var.region}:${var.account_id}:*"
        }
      }
    }]
  })

  execution_role_arn = var.existing_execution_role_arn != null ? var.existing_execution_role_arn : aws_iam_role.execution[0].arn
  task_role_arn      = var.existing_task_role_arn != null ? var.existing_task_role_arn : aws_iam_role.task[0].arn

  application_containers = [
    for name, container in var.containers : merge(
      {
        name      = name
        image     = aws_ssm_parameter.image[name].value
        essential = container.essential
        environment = [
          for environment_name in sort(keys(container.environment)) : {
            name  = environment_name
            value = container.environment[environment_name]
          }
        ]
        secrets = [
          for secret in container.secrets : {
            name      = secret.name
            valueFrom = secret.value_from
          }
        ]
        portMappings = [
          for port in container.ports : merge(
            {
              containerPort = port.container_port
              protocol      = port.protocol
            },
            port.host_port != null ? { hostPort = port.host_port } : {},
            port.name != null ? { name = port.name } : {},
            port.app_protocol != null ? { appProtocol = port.app_protocol } : {},
          )
        ]
        dependsOn = [
          for dependency in container.depends_on : {
            containerName = dependency.container_name
            condition     = upper(dependency.condition)
          }
        ]
        mountPoints = [
          for mount_point in container.mount_points : {
            sourceVolume  = mount_point.source_volume
            containerPath = mount_point.container_path
            readOnly      = mount_point.read_only
          }
        ]
        dockerLabels = container.docker_labels
      },
      length(container.command) > 0 ? { command = container.command } : {},
      length(container.entrypoint) > 0 ? { entryPoint = container.entrypoint } : {},
      container.working_directory != null ? { workingDirectory = container.working_directory } : {},
      container.health_check != null ? {
        healthCheck = merge(
          { command = container.health_check.command },
          container.health_check.interval != null ? { interval = container.health_check.interval } : {},
          container.health_check.timeout != null ? { timeout = container.health_check.timeout } : {},
          container.health_check.retries != null ? { retries = container.health_check.retries } : {},
          container.health_check.start_period != null ? { startPeriod = container.health_check.start_period } : {},
        )
      } : {},
      container.stop_timeout != null ? { stopTimeout = container.stop_timeout } : {},
      container.cpu != null ? { cpu = container.cpu } : {},
      container.memory != null ? { memory = container.memory } : {},
      container.memory_reservation != null ? { memoryReservation = container.memory_reservation } : {},
      var.datadog_enabled ? {
        logConfiguration = {
          logDriver = "awsfirelens"
          options = {
            Name           = "datadog"
            Host           = "http-intake.logs.datadoghq.com"
            TLS            = "on"
            provider       = "ecs"
            dd_service     = var.application_name
            dd_source      = "eventbrite"
            dd_tags        = "environment:${var.environment},service:${var.application_name}"
            dd_message_key = "log"
          }
          secretOptions = [{
            name      = "apikey"
            valueFrom = local.datadog_secret_arn
          }]
        }
        } : {
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.task.name
            "awslogs-region"        = var.region
            "awslogs-stream-prefix" = "ecs"
          }
        }
      },
    )
  ]
  datadog_agent_environment = merge(
    {
      DD_APM_ENABLED                 = tostring(var.datadog_apm_enabled)
      DD_DOGSTATSD_NON_LOCAL_TRAFFIC = "false"
      DD_ENV                         = var.environment
      DD_LOGS_ENABLED                = "false"
      DD_SITE                        = "datadoghq.com"
      DD_STATSD_METRIC_NAMESPACE     = "eb"
      DD_TAGS                        = "environment:${var.environment} service:${replace(lower(var.application_name), "/[^a-z0-9-]+/", "-")}"
      ECS_FARGATE                    = "true"
    },
    var.datadog_apm_enabled ? { DD_APM_NON_LOCAL_TRAFFIC = "true" } : {},
    var.datadog_agent_environment,
  )
  datadog_agent_container = {
    name              = "datadog-agent"
    image             = var.datadog_agent_image
    essential         = false
    cpu               = var.datadog_agent_cpu
    memoryReservation = var.datadog_agent_memory_reservation
    environment = [
      for name in sort(keys(local.datadog_agent_environment)) : {
        name  = name
        value = local.datadog_agent_environment[name]
      }
    ]
    secrets = [{
      name      = "DD_API_KEY"
      valueFrom = local.datadog_secret_arn
    }]
    portMappings = concat(
      [{ containerPort = 8125, hostPort = 8125, protocol = "udp" }],
      var.datadog_apm_enabled ? [{ containerPort = 8126, hostPort = 8126, protocol = "tcp" }] : [],
    )
  }
  firelens_container = {
    name              = "log-router"
    image             = var.firelens_image
    essential         = true
    cpu               = var.firelens_cpu
    memoryReservation = var.firelens_memory_reservation
    firelensConfiguration = {
      type = "fluentbit"
      options = {
        "enable-ecs-log-metadata" = "true"
      }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.task.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "firelens"
      }
    }
  }
  encoded_container_definitions = concat(
    [for container in local.application_containers : jsonencode(container)],
    [
      for container in [local.datadog_agent_container, local.firelens_container] :
      jsonencode(container) if var.datadog_enabled
    ],
  )
}

data "aws_secretsmanager_secret" "datadog" {
  count = var.datadog_enabled && var.datadog_api_key_secret_arn == null ? 1 : 0

  name = var.datadog_api_key_secret_name
}

# Terraform owns parameter metadata and the bootstrap value. Deployment automation owns subsequent image values.
resource "aws_ssm_parameter" "image" {
  for_each = var.containers

  name  = coalesce(each.value.image_parameter_name, "/ecs/${var.application_name}/${var.environment}/images/${each.key}")
  tags  = var.tags
  type  = "String"
  value = each.value.bootstrap_image

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_cloudwatch_log_group" "task" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_iam_role" "execution" {
  count = var.existing_execution_role_arn == null ? 1 : 0

  assume_role_policy = local.assume_ecs_tasks
  name               = "${var.name}-ecs-execution"
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  count = var.existing_execution_role_arn == null ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.execution[0].name
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = var.existing_execution_role_arn == null && length(local.execution_secret_arns) > 0 ? 1 : 0

  name = "secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = local.execution_secret_arns
    }]
  })
  role = aws_iam_role.execution[0].name
}

resource "aws_iam_role_policy" "execution_ssm_parameters" {
  count = var.existing_execution_role_arn == null && length(local.execution_ssm_parameter_arns) > 0 ? 1 : 0

  name = "ssm-parameters"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameters"
      Resource = local.execution_ssm_parameter_arns
    }]
  })
  role = aws_iam_role.execution[0].name
}

resource "aws_iam_role_policy" "execution_pull_through" {
  count = var.existing_execution_role_arn == null && length(var.execution_pull_through_repository_arns) > 0 ? 1 : 0

  name = "ecr-pull-through"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:BatchImportUpstreamImage",
        "ecr:CreateRepository",
      ]
      Resource = var.execution_pull_through_repository_arns
    }]
  })
  role = aws_iam_role.execution[0].name
}

resource "aws_iam_role" "task" {
  count = var.existing_task_role_arn == null ? 1 : 0

  assume_role_policy = local.assume_ecs_tasks
  name               = "${var.name}-ecs-task"
  tags               = var.tags
}

resource "aws_iam_role_policy" "task" {
  count = var.existing_task_role_arn == null && var.task_role_policy_json != null ? 1 : 0

  name   = "application"
  policy = var.task_role_policy_json
  role   = aws_iam_role.task[0].name
}

# Terraform owns task configuration and the bootstrap revision. Deployment automation updates SSM image values, registers image-only revisions, and updates services.
resource "aws_ecs_task_definition" "this" {
  container_definitions    = "[${join(",", local.encoded_container_definitions)}]"
  cpu                      = tostring(var.cpu)
  execution_role_arn       = local.execution_role_arn
  family                   = var.name
  memory                   = tostring(var.memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  skip_destroy             = true
  tags                     = var.tags
  task_role_arn            = local.task_role_arn
  track_latest             = true

  dynamic "volume" {
    for_each = var.volumes

    content {
      name = volume.key
    }
  }

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # Deployment automation registers image-only revisions after the bootstrap
  # revision; Terraform must not replace the live revision on the next apply.
  lifecycle {
    ignore_changes = [container_definitions]
  }
}
