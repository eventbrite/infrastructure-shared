# aws-ecs-scheduled-task

Creates a shared Fargate task definition, an EventBridge Scheduler schedule group, schedules, and a least-privilege Scheduler execution role.

Tasks run in caller-provided private subnets without public IP addresses. Application logs and metrics are sent to Datadog by default. Task CPU units (`task_cpu`) and memory in MiB (`task_memory`) are required. Use `aws-ecs-cluster` when the cluster also needs Container Insights.

## Usage

The example below creates the caller-owned network dependencies, an ECS cluster, and an hourly job. The job image's normal command is overridden by the schedule.

```hcl
# Legacy Eventbrite account VPCs use these names. TLZ deployments may need baseline
# SSM outputs or different data-source filters for their account-specific network.
data "aws_vpc" "legacy" {
  filter {
    name   = "tag:Name" # Match the existing legacy VPC by its Name tag.
    values = ["vpc-prod"]
  }
}

# Find private subnets in that VPC. Keep the VPC filter so similarly named subnets
# in another VPC cannot be selected accidentally.
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id" # Restrict the search to the VPC selected above.
    values = [data.aws_vpc.legacy.id]
  }

  filter {
    name   = "tag:Name" # The wildcard selects all legacy private subnets.
    values = ["prod-priv-*"]
  }
}

module "cluster" {
  source = "../infrastructure-shared/aws-ecs-cluster"

  service     = "example-job"
  environment = "prod"
}

resource "aws_security_group" "task" {
  name        = "example-job-tasks"
  description = "Security group for the example job task ENIs"
  vpc_id      = data.aws_vpc.legacy.id

  # Allow outbound traffic for Datadog telemetry, image pulls, and AWS API access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "scheduled_task" {
  source = "../infrastructure-shared/aws-ecs-scheduled-task"

  application_name   = "example-job"
  environment        = "prod"
  region             = "us-east-1"
  name               = "example-job-prod"
  cluster_arn        = module.cluster.arn
  subnets            = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.task.id]
  task_cpu           = 256
  task_memory        = 512

  containers = {
    job = {
      bootstrap_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/job@sha256:..."
    }
  }

  schedules = {
    hourly = {
      expression = "rate(1 hour)"
      command_overrides = {
        job = ["python", "-m", "jobs.hourly"]
      }
    }
  }
}
```

The default sidecar reservations are 10 CPU units and 256 MiB for the Datadog Agent, and 10 CPU units and 64 MiB for FireLens. Tune `datadog_agent_cpu`, `datadog_agent_memory_reservation`, `firelens_cpu`, and `firelens_memory_reservation` for the workload's telemetry volume and task size, keeping their combined reservations within `task_cpu` and `task_memory` alongside the application containers.

Each schedule supports an optional AWS name and description, expression, timezone, enabled state, retry limits, and container command overrides. The Scheduler role can run only the module's task definition family on the supplied cluster and can pass only the task's execution and runtime roles. Schedules are enabled by default, so set `enabled = false` while validating a migration or waiting for the application cutover.

## Runtime requirements

The provider account and `us-east-1` are used when `account_id` and `region` are omitted. Secrets Manager and SSM Parameter Store references supplied as ARNs in `containers` are automatically added to a module-created execution role; use `execution_secret_arns` for additional Secrets Manager secrets. Name-based references and SSM parameters encrypted with customer-managed KMS keys require a caller-managed execution role with the corresponding permissions.

Datadog is enabled by default and requires the existing `datadog/api-key` Secrets Manager secret. Set `datadog_enabled = false` only when the workload intentionally uses CloudWatch-only logs and metrics. Use `datadog_agent_environment` for workload-specific Agent settings; supplied values override the defaults.

If a task pulls an image through an ECR pull-through cache, pass the exact cache repository ARNs in `execution_pull_through_repository_arns`. The permission is deliberately not granted to an entire cache prefix.

Private tasks need NAT or the required VPC endpoints for ECR image pulls, CloudWatch Logs, Secrets Manager, SSM, and Datadog intake.
