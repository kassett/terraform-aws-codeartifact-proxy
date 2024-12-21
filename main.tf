
data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

locals {
  TRACKED_GIT_VERSION = "0.1.18"

  region           = coalesce(var.codeartifact_region, data.aws_region.this.name)
  account_id       = coalesce(var.codeartifact_account_id, data.aws_caller_identity.this.account_id)
  image_name       = "codeartifact-proxy"
  image_repository = "kassett247"
  image_tag        = coalesce(var.proxy_image_tag, local.TRACKED_GIT_VERSION)
}

resource "aws_ecs_cluster" "cluster" {
  count = var.create_cluster ? 1 : 0
  name  = var.cluster_name
  tags  = var.cluster_tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.proxy_task_definition_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = local.image_name,
      image     = "${local.image_repository}/${local.image_name}:${local.image_tag}",
      essential = true,
      portMappings = [
        {
          containerPort = var.proxy_container_port
          hostPort      = var.proxy_host_port
          protocol      = "TCP"
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = data.aws_region.this.name
          "awslogs-stream-prefix" = "ecs"
        }
      },
      environment = [
        {
          name  = "PROXY_REGION"
          value = var.codeartifact_region
        },
        {
          name  = "PROXY_ACCOUNT_ID"
          value = var.codeartifact_account_id
        },
        {
          name = "PROXY_DOMAIN"
          value = var.codeartifact_domain
        },
        {
          name = "PROXY_REPOSITORY"
          value = var.codeartifact_repository
        },
        {
          name = "PROXY_USERNAME"
          value = coalesce(var.username, "")
        },
        {
          name = "PROXY_PASSWORD"
          value = coalesce(var.password, "")
        },
        {
          name = "PROXY_ALLOW_ANONYMOUS"
          value = var.allow_anonymous_access
        },
        {
          name = "PROXY_SERVER_PORT"
          value = var.proxy_container_port
        }
      ],
    }
  ])
}