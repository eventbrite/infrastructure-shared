# aws-ecs-service

Creates an ECS Fargate service and task definition with optional CPU target-tracking autoscaling.

The cluster, private subnets, security groups, load balancer, and target groups are caller-owned. Tasks use private networking and send application logs and metrics to Datadog by default. Use `aws-ecs-cluster` when the cluster also needs Container Insights.

Application images are bootstrapped into SSM parameters. Deployment automation updates those parameters, registers image-only task-definition revisions, and updates the service. Terraform tracks the task definition family but ignores live task revisions and desired counts so subsequent applies do not revert deployments or autoscaling adjustments. Task CPU units (`task_cpu`) and memory in MiB (`task_memory`) are required.

Secrets referenced by application containers through Secrets Manager or SSM Parameter Store ARNs are automatically granted to a module-created execution role. Add `execution_secret_arns` for additional Secrets Manager secrets. Name-based references and SSM parameters encrypted with customer-managed KMS keys require a caller-managed execution role with the corresponding permissions.

If a task pulls an image through an ECR pull-through cache, pass the exact cache repository ARNs in `execution_pull_through_repository_arns`. The permission is deliberately not granted to an entire cache prefix.

## Usage

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

  service     = "example"
  environment = "prod"
}

module "service" {
  source = "../infrastructure-shared/aws-ecs-service"

  cluster_arn        = module.cluster.arn
  environment        = "prod"
  security_group_ids = [aws_security_group.service.id] # Caller-owned task ENI security group.
  service            = "example"                       # Service and task family become example-prod.
  subnets            = data.aws_subnets.private.ids
  task_cpu           = 256
  task_memory        = 512

  # Set exactly one of autoscaling or desired_count.
  # CPU target tracking defaults to 70%, with 60s scale-out and 300s scale-in cooldowns.
  # Set this to null and provide desired_count instead to disable autoscaling.
  autoscaling = {
    min_capacity = 1
    max_capacity = 10
  }

  containers = {
    app = {
      bootstrap_image = "public.ecr.aws/docker/library/nginx:1.27"
      environment = {
        NGINX_ENTRYPOINT_QUIET_LOGS = "1"
      }
      ports = [{
        container_port = 80 # Port nginx listens on inside the task.
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

  # Optional: attach an existing ALB/NLB target group. The target group must use
  # ip targets and point at the mapped container port.
  load_balancers = [{
    target_group_arn = aws_lb_target_group.example.arn
    container_name   = "app"
    container_port   = 80
  }]
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

The default sidecar reservations are 10 CPU units and 256 MiB for the Datadog Agent, and 10 CPU units and 64 MiB for FireLens. Tune `datadog_agent_cpu`, `datadog_agent_memory_reservation`, `firelens_cpu`, and `firelens_memory_reservation` for the workload's telemetry volume and task size, keeping their combined reservations within `task_cpu` and `task_memory` alongside the application containers.

## Runtime requirements

The module creates an empty task role by default. Supply `task_role_policy_json` when the application calls AWS APIs, or supply caller-managed execution and task role ARNs when IAM is owned elsewhere.

Datadog is enabled by default and requires the existing `datadog/api-key` Secrets Manager secret. Set `datadog_enabled = false` only when the workload intentionally uses CloudWatch-only logs and metrics. Use `datadog_agent_environment` for workload-specific Agent settings such as DogStatsD mapper profiles; supplied values override the defaults.

Private tasks need NAT or the required VPC endpoints for ECR image pulls, CloudWatch Logs, Secrets Manager, SSM, and Datadog intake.
