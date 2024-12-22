
data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

locals {
  TRACKED_GIT_VERSION = "0.1.22"

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

resource "aws_vpc_security_group_egress_rule" "internet_access" {
  count             = length(var.networking.security_groups) == 0 ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Internet access for pulling image and artifacts."
  ip_protocol       = "-1"
}

locals {
  security_groups = length(var.networking.security_groups) > 0 ? var.networking.security_groups : [try(aws_security_group.sg[0].id)]
}

resource "aws_cloudwatch_log_group" "lg" {
  name = var.names.log_group
}

resource "aws_secretsmanager_secret" "auth" {
  count       = var.authentication.allow_anonymous ? 0 : 1
  name_prefix = var.names.secret_prefix
}

resource "aws_secretsmanager_secret_version" "auth" {
  count     = var.authentication.allow_anonymous ? 0 : 1
  secret_id = aws_secretsmanager_secret.auth[0].id
  secret_string = jsonencode({
    username = var.authentication.username
    password = var.authentication.password
  })
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.names.task_definition
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = local.image_name,
      image     = "${local.image_repository}/${local.image_name}:${local.image_tag}",
      essential = true,
      cpu       = var.task_cpu
      memory    = var.task_memory
      portMappings = [
        {
          containerPort = var.networking.container_port
          hostPort      = var.networking.container_port
          protocol      = "HTTP"
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.lg.name
          "awslogs-region"        = data.aws_region.this.name
          "awslogs-stream-prefix" = "ecs"
        }
      },
      environment = concat([
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
        ], var.authentication.allow_anonymous ? [] : [
        {
          name  = "PROXY_SECRET_ID"
          value = try(aws_secretsmanager_secret.auth[0].id)
        }
      ])
    }
  ])
  depends_on = [aws_cloudwatch_log_group.lg]
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

  load_balancer {
    container_name   = local.image_name
    container_port   = var.networking.container_port
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags       = var.tags.service
  depends_on = [aws_ecs_cluster.cluster]
}

resource "aws_lb" "this" {
  name               = var.names.load_balancer
  internal           = true
  load_balancer_type = "application"
  security_groups    = local.security_groups
  subnets            = var.networking.subnets
}

resource "aws_lb_target_group" "this" {
  name        = var.names.load_balancer_target_group
  port        = var.networking.host_port
  protocol    = "HTTP"
  vpc_id      = var.networking.vpc_id
  target_type = "ip"
  health_check {
    path                = "/"
    interval            = var.networking.health_check.interval
    timeout             = var.networking.health_check.timeout
    healthy_threshold   = var.networking.health_check.healthy_threshold
    unhealthy_threshold = var.networking.health_check.unhealthy_threshold
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.networking.host_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
