
data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

locals {
  TRACKED_GIT_VERSION = "0.1.19"

  codeartifact_region     = coalesce(var.repository_settings.region, data.aws_region.this.name)
  codeartifact_account_id = coalesce(var.repository_settings.account_id, data.aws_caller_identity.this.account_id)
  image_name              = "codeartifact-proxy"
  image_repository        = "kassett247"
  image_tag               = coalesce(var.image_tag, local.TRACKED_GIT_VERSION)
}

resource "aws_ecs_cluster" "cluster" {
  count = var.create_cluster ? 1 : 0
  name  = var.names.cluster
  tags  = var.tags.cluster
}

resource "aws_security_group" "sg" {
  count       = length(var.networking.security_groups) == 0 ? 1 : 0
  vpc_id      = var.networking.vpc_id
  name_prefix = var.names.security_group_prefix
  description = "Default security group created to give access to the CodeArtifact Proxy."
}

locals {
  security_groups = length(var.networking.security_groups) > 0 ? var.networking.security_groups : [try(aws_security_group.sg[0].id)]
}

resource "aws_cloudwatch_log_group" "lg" {
  name = var.names.log_group
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.names.task_definition
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
          containerPort = var.networking.container_port
          hostPort      = var.networking.host_port
          protocol      = "TCP"
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.names.log_group
          "awslogs-region"        = data.aws_region.this.name
          "awslogs-stream-prefix" = "ecs"
        }
      },
      environment = [
        {
          name  = "PROXY_REGION"
          value = local.codeartifact_region
        },
        {
          name  = "PROXY_ACCOUNT_ID"
          value = local.codeartifact_account_id
        },
        {
          name  = "PROXY_DOMAIN"
          value = var.repository_settings.domain
        },
        {
          name  = "PROXY_REPOSITORY"
          value = var.repository_settings.repository
        },
        {
          name  = "PROXY_ALLOW_ANONYMOUS"
          value = tostring(var.authentication.allow_anonymous)
        },
        {
          name  = "PROXY_SERVER_PORT"
          value = tostring(var.networking.container_port)
        }
      ]
      secret = concat(var.authentication.username != null ? [
        {
          name  = "PROXY_USERNAME"
          value = var.authentication.username
        }
        ] : [], var.authentication.password != null ? [
        {
          name  = "PROXY_PASSWORD"
          value = var.authentication.password
        }
      ] : [])
    }
  ])
}

resource "aws_ecs_service" "this" {
  name                  = var.names.service
  cluster               = var.names.cluster
  task_definition       = aws_ecs_task_definition.this.arn
  desired_count         = var.replicas
  wait_for_steady_state = true
  launch_type           = "FARGATE"

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = local.security_groups
    subnets          = var.networking.subnets
  }

  tags       = var.tags.service
  depends_on = [aws_ecs_cluster.cluster]
}