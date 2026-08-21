variable "account_id" {
  description = "Optional AWS account ID containing the GitHub OIDC provider and deploy role. The provider account is used when omitted."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.account_id == null ? true : can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "base_image_arns" {
  description = "ECR repository ARNs from which CI may pull base images."
  type        = list(string)
  default     = []
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs to which CI may push application images."
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "ecr_repository_arns must contain at least one repository ARN."
  }
}

variable "ecs_deployment" {
  description = "Optional ECS rollout permissions for one cluster, its services, and the task roles passed during registration."
  type = object({
    cluster_arn  = string
    role_arns    = list(string)
    service_arns = list(string)
  })
  default  = null
  nullable = true

  validation {
    condition = var.ecs_deployment == null ? true : (
      length(var.ecs_deployment.service_arns) > 0 &&
      length(var.ecs_deployment.role_arns) > 0
    )
    error_message = "ecs_deployment must include at least one service ARN and task role ARN."
  }
}

variable "extra_policy_statements" {
  description = "Additional IAM policy statements for exceptional build-handoff requirements."
  type = list(object({
    actions   = list(string)
    condition = optional(map(map(list(string))), {})
    effect    = optional(string, "Allow")
    resources = list(string)
    sid       = optional(string)
  }))
  default = []
}

variable "environment" {
  description = "AWS and GitHub Actions environment trusted to assume the role."
  type        = string
}

variable "image_parameter_arns" {
  description = "SSM image parameter ARNs CI may update."
  type        = list(string)

  validation {
    condition     = length(var.image_parameter_arns) > 0
    error_message = "image_parameter_arns must contain at least one parameter ARN."
  }
}

variable "repository" {
  description = "GitHub repository in owner/name form."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.repository))
    error_message = "repository must use owner/name form."
  }
}

variable "role_name" {
  description = "IAM role name. A repository and environment derived name is used when omitted."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags to apply to the IAM role."
  type        = map(string)
  default     = {}
}
