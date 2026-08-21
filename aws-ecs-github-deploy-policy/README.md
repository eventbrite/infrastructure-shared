# aws-ecs-github-deploy-policy

Creates an IAM role for GitHub Actions to build and publish an application image. It can also grant the permissions required to register an ECS task definition and update an ECS service.

The role is assumed through GitHub OIDC. Trust is restricted to one repository and one environment using exact `aud` and `sub` claims.

## Usage

The GitHub OIDC provider, ECR repository, ECS resources, task roles, and SSM image parameters are caller-owned. The GitHub environment must match `environment`, and the workflow must request an OIDC token with audience `sts.amazonaws.com`.

```hcl
data "aws_ecr_repository" "application" {
  name = "example"
}

module "github_deploy" {
  source = "../infrastructure-shared/aws-ecs-github-deploy-policy"

  ecr_repository_arns  = [data.aws_ecr_repository.application.arn]
  environment          = "production"
  image_parameter_arns = values(module.service.image_parameter_arns)
  repository           = "eventbrite/example"

  # Optional private ECR base images used by the Docker build.
  # base_image_arns = [data.aws_ecr_repository.base.arn]

  # Include when the workflow performs an ECS rollout.
  ecs_deployment = {
    cluster_arn  = module.cluster.arn
    role_arns    = [module.service.execution_role_arn, module.service.task_role_arn]
    service_arns = [module.service.service_arn]
  }

  # Extra statements should use the smallest required actions and resources.
  # extra_policy_statements = []
}
```
