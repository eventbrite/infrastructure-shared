data "aws_caller_identity" "current" {}

locals {
  account_id = coalesce(var.account_id, data.aws_caller_identity.current.account_id)

  ecs_deployment_statements = flatten([
    for deployment in [var.ecs_deployment] : [
      {
        Sid    = "RegisterTaskDefinitions"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
        ]
        Resource = "*" # RegisterTaskDefinition has no resource-level permissions.
      },
      {
        Sid      = "ListClusterServices"
        Effect   = "Allow"
        Action   = "ecs:ListServices"
        Resource = "*" # ListServices has no resource-level permissions.
        Condition = {
          ArnEquals = {
            "ecs:cluster" = deployment.cluster_arn
          }
        }
      },
      {
        Sid    = "DeployServices"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
        ]
        Resource = deployment.service_arns
      },
      {
        Sid       = "PassTaskRoles"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = deployment.role_arns
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
    ] if deployment != null
  ])
  policy_statements = concat(
    [
      {
        Sid      = "ECRAuthorization"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushApplicationImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = var.ecr_repository_arns
      },
      {
        Sid      = "PublishImageParameters"
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameter",
          "ssm:PutParameter",
        ]
        Resource = var.image_parameter_arns
      },
    ],
    length(var.base_image_arns) > 0 ? [{
      Sid    = "PullBaseImages"
      Effect = "Allow"
      Action = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      Resource = var.base_image_arns
    }] : [],
    local.ecs_deployment_statements,
    [
      for statement in var.extra_policy_statements : merge(
        {
          Effect   = statement.effect
          Action   = statement.actions
          Resource = statement.resources
        },
        statement.sid != null ? { Sid = statement.sid } : {},
        length(statement.condition) > 0 ? { Condition = statement.condition } : {},
      )
    ],
  )
}

resource "aws_iam_role" "this" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.repository}:environment:${var.environment}"
        }
      }
    }]
  })
  name = coalesce(
    var.role_name,
    "${replace(var.repository, "/", "-")}-${var.environment}-deploy",
  )
  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  name = "image-build-handoff"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.policy_statements
  })
  role = aws_iam_role.this.name
}
