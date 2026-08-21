# aws-ecs-cluster

Creates one ECS cluster with [Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html) enabled.

## Usage

```hcl
module "cluster" {
  source = "github.com/eventbrite/infrastructure-shared//aws-ecs-cluster?ref=aws-ecs-cluster-0.1.0"

  service     = "example"
  environment = "prod"
}
```

The cluster name is derived as `<service>-<environment>`.
