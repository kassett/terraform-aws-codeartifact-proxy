
locals {
  repository_config_file = base64encode(jsonencode([for hos in var.repositories : {
    hosts                    = concat([hos.hostname], hos.additional_hosts)
    code_artifact_domain     = hos.domain
    code_artifact_repository = hos.repository
    package_manager_format   = hos.package_manager
  }]))
}

resource "aws_ecs_cluster" "cluster" {
  count = var.create_cluster ? 1 : 0
  name  = var.names.cluster
  tags  = merge(var.default_tags, var.tags.cluster)
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.names.task_definition
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

  tags  = merge(var.default_tags, var.tags.task_definition)

  volume {
    name = "config"
  }

  container_definitions = jsonencode([
    {
      name      = "config-writer"
      image     = "alpine:latest"
      essential = false
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/cap"
        }
      ],
      command = [
        "sh",
        "-c",
        "echo '${local.repository_config_file}' | base64 -d - | tee /etc/cap/config.json"
      ]
    },
    {
      name      = local.image_name,
      image     = "${local.image_repository}/${local.image_name}:${local.image_tag}",
      essential = true
      dependsOn = [
        {
          containerName = "config-writer"
          condition     = "COMPLETE"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/cap"
        }
      ]

      # Unfortunately, AWS provides no way to mount a single file
      # It is an open issue but there seems to be no progress on it
      # https://github.com/aws/containers-roadmap/issues/56

      # Using an entrypoint ensures no race condition,
      # as opposed to potentially using a different container
      cpu    = var.task_cpu
      memory = var.task_memory
      portMappings = [
        {
          containerPort = var.networking.container_port
          hostPort      = var.networking.container_port
          protocol      = "tcp"
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
          name  = "CAP_REGION"
          value = data.aws_region.this.name
        },
        {
          name  = "CAP_ACCOUNT_ID"
          value = data.aws_caller_identity.this.account_id
        },
        {
          name  = "CAP_ALLOW_ANONYMOUS"
          value = tostring(var.authentication.allow_anonymous)
        },
        {
          name  = "CAP_PORT"
          value = tostring(var.networking.container_port)
        },
        {
          name  = "CAP_CONFIG_PATH"
          value = "/etc/cap/config.json"
        },
        {
          name  = "CAP_HEALTH_CHECK_PATH"
          value = var.networking.health_check.path
        }], var.authentication.allow_anonymous ? [] : [
        {
          name  = "CAP_AUTH_SECRET"
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
  wait_for_steady_state = false
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
    container_name = local.image_name
    container_port = var.networking.container_port
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags  = merge(var.default_tags, var.tags.service)
  depends_on = [aws_lb_listener.this, aws_ecs_cluster.cluster]
}
