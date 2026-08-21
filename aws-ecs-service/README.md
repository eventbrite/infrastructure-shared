# aws-ecs-service

Creates an ECS Fargate service and task definition with optional CPU target-tracking autoscaling. Tasks use private networking and send application logs and metrics to Datadog by default.

## Usage

```hcl
# The ECS cluster, private subnets, task security group, and optional target group are caller-owned.
# Private tasks need NAT or VPC endpoints for ECR, CloudWatch Logs, Secrets Manager, SSM, and Datadog intake.
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
  source = "github.com/eventbrite/infrastructure-shared//aws-ecs-cluster?ref=aws-ecs-cluster-0.1.0"

  service     = "example"
  environment = "prod"
}

module "service" {
  source = "github.com/eventbrite/infrastructure-shared//aws-ecs-service?ref=aws-ecs-service-0.1.0"

  cluster_arn        = module.cluster.arn
  environment        = "prod"
  security_group_ids = [aws_security_group.service.id]
  service            = "example"
  subnets            = data.aws_subnets.private.ids
  task_cpu           = 256
  task_memory        = 512

  # Set autoscaling to null and provide desired_count for a fixed task count.
  autoscaling = {
    min_capacity = 1
    max_capacity = 10
  }

  # Application images are bootstrapped through SSM image parameters.
  containers = {
    app = {
      bootstrap_image = "public.ecr.aws/docker/library/nginx:1.27"
      environment = {
        NGINX_ENTRYPOINT_QUIET_LOGS = "1"
      }
      ports = [{
        container_port = 80
        name           = "http"
        app_protocol   = "http"
      }]
      health_check = {
        command      = ["CMD", "nginx", "-t"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 10
      }
      stop_timeout = 30
    }
  }

  # Optional target group must use ip targets and the mapped container port.
  load_balancers = [{
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "app"
    container_port   = 80
  }]

  # Datadog and FireLens reserve 20 CPU units and 320 MiB by default.
  # datadog_enabled = false

  # ARN-based container secrets are granted automatically. Use these for extras,
  # pull-through cache repositories, or caller-managed IAM roles.
  # execution_secret_arns                       = [aws_secretsmanager_secret.extra.arn]
  # execution_pull_through_repository_arns      = [data.aws_ecr_repository.base.arn]
  # existing_execution_role_arn                  = aws_iam_role.execution.arn
  # existing_task_role_arn                       = aws_iam_role.task.arn
  # task_role_policy_json                        = data.aws_iam_policy_document.task.json
}

resource "aws_security_group" "service" {
  name        = "example-service-tasks"
  description = "Security group for the example ECS task ENIs"
  vpc_id      = data.aws_vpc.legacy.id

  # Allow outbound traffic for Datadog telemetry, image pulls, and AWS API access.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

## Deployment

To roll out a new image in CI, update the container's SSM image parameter, trigger a new deployment on the service, and wait for stabilization:

Deployment automation registers the new task-definition revision and updates the SSM parameter after a successful rollout. The task definition tracks the latest family revision, so subsequent Terraform plans retain the deployed image and task configuration.

```sh
aws ssm put-parameter \
  --name "/ecs/<service>/<environment>/images/<container>" \
  --value "$IMAGE_URI" \
  --type String \
  --overwrite

aws ecs update-service \
  --cluster "<cluster-name>" \
  --service "<service-name>" \
  --force-new-deployment

aws ecs wait services-stable \
  --cluster "<cluster-name>" \
  --services "<service-name>"
```
