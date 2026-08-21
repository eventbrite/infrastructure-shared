variable "environment" {
  description = "Deployment environment used to derive the ECS cluster name."
  type        = string
}

variable "service" {
  description = "Service name used to derive the ECS cluster name."
  type        = string
}

variable "tags" {
  description = "Tags to apply to the ECS cluster."
  type        = map(string)
  default     = {}
}
