# aws-ecs-github-deploy-policy

Creates an IAM role for GitHub Actions to build and publish an application image. It can also grant the permissions required to register an ECS task definition and update an ECS service.

The role is assumed through GitHub OIDC. Trust is restricted to one repository and one environment using exact `aud` and `sub` claims.

## Usage

The GitHub OIDC provider, ECR repository, ECS resources, task roles, and SSM image parameters are caller-owned. The GitHub environment must match `environment`, and the workflow must request an OIDC token with audience `sts.amazonaws.com`.

```hcl
module "github_deploy" {
  source = "../infrastructure-shared/aws-ecs-github-deploy-policy"

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

`account_id` defaults to the AWS provider account; set it only when the GitHub OIDC provider and deploy role are in a different account. The role name defaults to `<repository-with-slashes-replaced>-<environment>-deploy`.

Pass private ECR base-image repository ARNs in `base_image_arns`. The application repositories receive image push permissions, including `ecr:DescribeImages` for immutable SHA tag checks.

Set `ecs_deployment` when the workflow performs an ECS rollout. It grants task-definition registration, service listing and updates, and `iam:PassRole` for the supplied task execution and task role ARNs.

Use `extra_policy_statements` only for additional scoped permissions.
