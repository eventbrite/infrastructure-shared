# aws-ecs-task-definition

Private implementation module for `aws-ecs-service` and `aws-ecs-scheduled-task`. It creates the shared Fargate task definition, SSM image parameters, CloudWatch log group, FireLens/Datadog containers, and optional ECS roles.

Use the public modules instead. `datadog_agent_environment` customizes Agent settings without replacing the standard sidecar. Caller-managed execution and task roles remain fully caller-owned.
