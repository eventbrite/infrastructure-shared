# infrastructure-shared

Reusable Terraform modules for Eventbrite infrastructure.

## Modules

| Module | Purpose |
| --- | --- |
| [`aws-ecs-cluster`](./aws-ecs-cluster) | A minimal ECS cluster with Container Insights |
| [`aws-ecs-service`](./aws-ecs-service) | A Fargate service, task definition, and CPU autoscaling |
| [`aws-ecs-scheduled-task`](./aws-ecs-scheduled-task) | Fargate tasks launched by EventBridge Scheduler |

Modules in the `_` folder are not versioned explicitly and are considered internal implementation details for other modules. It is a way to reuse code and enforce consistency without adding additional public modules.

Each public module is versioned independently with tags named after the module directory, for example `aws-ecs-service-0.1.0`.

## Contributing

1. Change only the affected module and its private dependencies.
2. Add release notes to the affected public module's next top-level semantic-version heading.
3. Run `terraform fmt -check -recursive .`.
4. In every changed module directory, run `terraform init -backend=false -input=false` followed by `terraform validate`.

Pull requests run formatting, validation, and release-metadata checks for every module. The release check reports the exact changelog update needed when source changes lack a new version.

## Releasing

1. Add a new top-level semantic-version heading to each affected public module's `CHANGELOG.md`.
2. For changes to the private task-definition module, update the changelog heading for all public modules that consume it.
3. Open and merge the pull request after CI passes.
4. The push to `main` runs the release workflow, which creates annotated tags and GitHub Releases in the form `<module>-<version>`.

Releases are published automatically after a merge to `main`; there is no manual release step.
