# aws-ecs-cluster

Creates one ECS cluster with [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html) enabled.

## Usage

```hcl
module "cluster" {
  source = "../infrastructure-shared/aws-ecs-cluster"

  service     = "example"
  environment = "prod"
}
```

The cluster name is derived as `<service>-<environment>`.
