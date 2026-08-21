variable "account_id" {
  description = "Optional AWS account ID used to scope IAM trust and permissions. The provider account is used when omitted."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.account_id == null || can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "application_name" {
  description = "Application identity used in image parameter paths and observability tags."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster."
  type        = string
}

variable "containers" {
  description = "Application containers keyed by container name. Images are bootstrapped through SSM parameters."
  type = map(object({
    bootstrap_image = string
    command         = optional(list(string), [])
    cpu             = optional(number)
    depends_on = optional(list(object({
      condition      = string
      container_name = string
    })), [])
    docker_labels = optional(map(string), {})
    entrypoint    = optional(list(string), [])
    environment   = optional(map(string), {})
    essential     = optional(bool, true)
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number)
      retries      = optional(number)
      start_period = optional(number)
      timeout      = optional(number)
    }))
    image_parameter_name = optional(string)
    memory               = optional(number)
    memory_reservation   = optional(number)
    mount_points = optional(list(object({
      container_path = string
      read_only      = optional(bool, false)
      source_volume  = string
    })), [])
    ports = optional(list(object({
      app_protocol   = optional(string)
      container_port = number
      host_port      = optional(number)
      name           = optional(string)
      protocol       = optional(string, "tcp")
    })), [])
    secrets = optional(list(object({
      name       = string
      value_from = string
    })), [])
    stop_timeout      = optional(number)
    working_directory = optional(string)
  }))

  validation {
    condition = alltrue(flatten([
      for container in values(var.containers) : [
        for port in container.ports : (
          port.container_port >= 1 &&
          port.container_port <= 65535 &&
          (port.host_port == null || (port.host_port >= 1 && port.host_port <= 65535)) &&
          contains(["tcp", "udp"], lower(port.protocol))
        )
      ]
    ]))
    error_message = "Container ports must be between 1 and 65535 and use tcp or udp."
  }

  validation {
    condition = alltrue(flatten([
      for container in values(var.containers) : [
        for dependency in container.depends_on : contains(keys(var.containers), dependency.container_name) && contains(
          ["START", "COMPLETE", "SUCCESS", "HEALTHY"],
          upper(dependency.condition),
        )
      ]
    ]))
    error_message = "Container dependencies must reference an application container and use START, COMPLETE, SUCCESS, or HEALTHY."
  }

  validation {
    condition     = anytrue([for container in values(var.containers) : container.essential])
    error_message = "At least one application container must be essential."
  }
}

variable "datadog_agent_cpu" {
  description = "CPU units reserved for the Datadog Agent sidecar."
  type        = number
  default     = 10

  validation {
    condition     = var.datadog_agent_cpu >= 0
    error_message = "datadog_agent_cpu must be non-negative."
  }
}

variable "datadog_agent_environment" {
  description = "Additional or overriding Datadog Agent environment variables."
  type        = map(string)
  default     = {}
}

variable "datadog_agent_image" {
  description = "Pinned Datadog Agent image for the linux/amd64 Fargate task."
  type        = string
  # Datadog Agent v7.82.2, linux/amd64.
  default = "public.ecr.aws/datadog/agent@sha256:435894160462b29e33ec8f4e4c7199a3e2498e137dd0d9551a18ffeb77bc4bf7"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.datadog_agent_image))
    error_message = "datadog_agent_image must use a sha256 digest."
  }
}

variable "datadog_agent_memory_reservation" {
  description = "Soft memory reservation in MiB for the Datadog Agent sidecar."
  type        = number
  default     = 256

  validation {
    condition     = var.datadog_agent_memory_reservation >= 0
    error_message = "datadog_agent_memory_reservation must be non-negative."
  }
}

variable "datadog_api_key_secret_arn" {
  description = "ARN of the existing Datadog API key secret."
  type        = string
  default     = null
  nullable    = true
}

variable "datadog_api_key_secret_name" {
  description = "Name of the existing Datadog API key secret."
  type        = string
  default     = "datadog/api-key"
}

variable "datadog_apm_enabled" {
  description = "Whether Datadog APM intake is enabled."
  type        = bool
  default     = false
}

variable "datadog_enabled" {
  description = "Whether the Datadog agent and FireLens log router are injected."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Deployment environment."
  type        = string
}

variable "execution_pull_through_repository_arns" {
  description = "Specific ECR pull-through cache repository ARNs that the execution role may create and import from upstream."
  type        = list(string)
  default     = []
}

variable "execution_secret_arns" {
  description = "Additional Secrets Manager ARNs the ECS execution role may read. Secrets Manager and SSM parameter references supplied as ARNs are included automatically."
  type        = list(string)
  default     = []
}

variable "existing_execution_role_arn" {
  description = "Optional caller-managed ECS execution role ARN. When set, the caller owns its trust and permissions."
  type        = string
  default     = null
  nullable    = true
}

variable "existing_task_role_arn" {
  description = "Optional caller-managed ECS task role ARN. When set, the caller owns its trust and permissions."
  type        = string
  default     = null
  nullable    = true
}

variable "firelens_cpu" {
  description = "CPU units reserved for the FireLens sidecar."
  type        = number
  default     = 10

  validation {
    condition     = var.firelens_cpu >= 0
    error_message = "firelens_cpu must be non-negative."
  }
}

variable "firelens_image" {
  description = "Pinned AWS for Fluent Bit image for the linux/amd64 Fargate task."
  type        = string
  # AWS for Fluent Bit v2.34.3.20260805, linux/amd64.
  default = "public.ecr.aws/aws-observability/aws-for-fluent-bit@sha256:d3d6dcd80f23eeb06bc0612285545204a62ffe6feff9dea8a637a8d7236d7c27"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.firelens_image))
    error_message = "firelens_image must use a sha256 digest."
  }
}

variable "firelens_memory_reservation" {
  description = "Soft memory reservation in MiB for the FireLens sidecar."
  type        = number
  default     = 64

  validation {
    condition     = var.firelens_memory_reservation >= 0
    error_message = "firelens_memory_reservation must be non-negative."
  }
}

variable "name" {
  description = "Task definition family and default schedule group name."
  type        = string
}

variable "region" {
  description = "AWS region containing the ECS workload."
  type        = string
  default     = "us-east-1"
}

variable "schedule_group_name" {
  description = "EventBridge Scheduler schedule group name. Defaults to name."
  type        = string
  default     = null
  nullable    = true
}

variable "schedules" {
  description = "Schedules keyed by stable Terraform identifier."
  type = map(object({
    command_overrides   = optional(map(list(string)), {})
    description         = optional(string)
    enabled             = optional(bool, true)
    expression          = string
    maximum_event_age   = optional(number, 300)
    maximum_retry_count = optional(number, 0)
    name                = optional(string)
    timezone            = optional(string, "UTC")
  }))
  default = {}

  validation {
    condition = alltrue([
      for schedule in values(var.schedules) : (
        schedule.maximum_event_age >= 60 &&
        schedule.maximum_event_age <= 86400 &&
        schedule.maximum_retry_count >= 0 &&
        schedule.maximum_retry_count <= 185
      )
    ])
    error_message = "maximum_event_age must be between 60 and 86400 seconds and maximum_retry_count must be between 0 and 185."
  }
}

variable "security_group_ids" {
  description = "Security groups attached to scheduled tasks."
  type        = list(string)
}

variable "subnets" {
  description = "Private subnet IDs used by scheduled tasks."
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
}

variable "task_role_policy_json" {
  description = "Optional IAM policy JSON attached to a task role created by this module."
  type        = string
  default     = null
  nullable    = true
}

variable "volumes" {
  description = "Names of empty ephemeral task volumes shared by containers."
  type        = set(string)
  default     = []
}
