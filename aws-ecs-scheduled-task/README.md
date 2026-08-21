# aws-ecs-scheduled-task

Creates a shared Fargate task definition, an EventBridge Scheduler schedule group, schedules, and a least-privilege Scheduler execution role. Tasks run in caller-provided private subnets without public IP addresses. Application logs and metrics are sent to Datadog by default.

## Usage

The ECS cluster, private subnets, and task security group are caller-owned. Private tasks need NAT or VPC endpoints for ECR, CloudWatch Logs, Secrets Manager, SSM, and Datadog intake.

```hcl
# Legacy Eventbrite account VPCs use these names.
data "aws_vpc" "legacy" {
  filter {
    name   = "tag:Name"
    values = ["vpc-prod"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.legacy.id]
  }

  filter {
    name   = "tag:Name"
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

  # Application images are bootstrapped through SSM image parameters.
  containers = {
    job = {
      bootstrap_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/job@sha256:..."
    }
  }

  # Override the image command for this schedule. Schedules are enabled by default.
  schedules = {
    hourly = {
      expression = "rate(1 hour)"
      command_overrides = {
        job = ["python", "-m", "jobs.hourly"]
      }
    }
  }

  # Datadog and FireLens reserve 20 CPU units and 320 MiB by default.
  # datadog_enabled = false

  # ARN-based container secrets are granted automatically. Use these for extras,
  # pull-through cache repositories, or caller-managed IAM roles.
  # execution_secret_arns                       = [aws_secretsmanager_secret.extra.arn]
  # execution_pull_through_repository_arns      = [data.aws_ecr_repository.base.arn]
  # existing_execution_role_arn                  = aws_iam_role.execution.arn
  # existing_task_role_arn                       = aws_iam_role.task.arn
}
```
