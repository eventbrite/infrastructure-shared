# aws-ecs-github-deploy-policy

Creates an IAM role for GitHub Actions to build and publish an application image. It can also grant the permissions required to register an ECS task definition and update an ECS service.

The role is assumed through GitHub OIDC. Trust is restricted to one repository and one environment using exact `aud` and `sub` claims. Use the same environment value in AWS and GitHub; this module does not translate between names. The GitHub OIDC provider must already exist in the account; this module does not create it.

## Usage

The example assumes that the caller owns the ECR repository and that `aws-ecs-cluster` and `aws-ecs-service` provide the cluster, service, task roles, and image parameter ARNs.

```hcl
data "aws_caller_identity" "current" {}

module "github_deploy" {
  source = "../infrastructure-shared/aws-ecs-github-deploy-policy"

  account_id           = data.aws_caller_identity.current.account_id
  ecr_repository_arns  = [aws_ecr_repository.application.arn]
  environment          = "production"
  image_parameter_arns = values(module.service.image_parameter_arns)
  repository           = "eventbrite/example"

  ecs_deployment = {
    cluster_arn  = module.cluster.arn
    role_arns    = [module.service.execution_role_arn, module.service.task_role_arn]
    service_arns = [module.service.service_arn]
  }
}
```

The role name defaults to `<repository-with-slashes-replaced>-<environment>-deploy`. Set `role_name` only when a caller-owned naming convention requires it. The module returns the role ARN for attaching to GitHub Actions configuration.

The application ECR repositories receive authentication, push, pull, and `ecr:DescribeImages` permissions. `ecr:DescribeImages` allows a build workflow to skip an image whose immutable SHA tag already exists. Pass base-image repository ARNs in `base_image_arns` when the Docker build pulls private ECR base images. The module does not create or configure ECR repositories.

The image parameter ARNs receive only `ssm:PutParameter`. These are the SSM parameters created by the ECS task modules and updated by deployment automation.

Set `ecs_deployment` only when the workflow also performs an ECS rollout. It grants task-definition registration, service listing and updates, and `iam:PassRole` for the supplied task execution and task role ARNs. `ecs:ListServices` is scoped to `cluster_arn` through its condition because AWS does not support resource-level permissions for that action. Task-definition registration also requires `Resource = "*"` because AWS does not support resource-level permissions for `ecs:RegisterTaskDefinition`.

Use `extra_policy_statements` only for permissions not covered by the standard image-build and ECS rollout paths. Keep those statements scoped to the smallest required resources and actions.

## Runtime requirements

The GitHub repository must use an environment whose name exactly matches `environment`, and the workflow must request an OIDC token with audience `sts.amazonaws.com`. The account must contain the GitHub OIDC provider and the caller-owned ECR repositories, ECS resources, IAM task roles, and SSM image parameters referenced by the module.
