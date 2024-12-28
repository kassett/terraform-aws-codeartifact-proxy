
locals {
  config_file_location = "/app/config.json"
  repository_config_file = jsonencode([ for hos in var.repositories : {
    Hosts = concat(hos.hostname, hos.additional_hosts)
    CodeArtifactDomain = hos.domain
    CodeArtifactRepository = hos.repository
  }])
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

      # Unfortunately, AWS provides no way to mount a single file
      # It is an open issue but there seems to be no progress on it
      # https://github.com/aws/containers-roadmap/issues/56

      # Using an entrypoint ensures no race condition,
      # as opposed to potentially using a different container
      entryPoint = [
        "/bin/bash",
        "-c",
        "echo '${local.repository_config_file}' > /app/config.json"
      ]
      cpu       = var.task_cpu
      memory    = var.task_memory
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
          name = "CAP_CONFIG_PATH"
          value = local.config_file_location
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