
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_task_allow" {
  statement {
    effect  = "Allow"
    actions = ["codeartifact:*"]
    resources = [
      "arn:aws:codeartifact:${local.codeartifact_region}:${local.codeartifact_account_id}:repository/${var.repository_settings.domain}/${var.repository_settings.repository}",
      "arn:aws:codeartifact:${local.codeartifact_region}:${local.codeartifact_account_id}:repository/${var.repository_settings.domain}/${var.repository_settings.repository}/*"
    ]
  }
}

data "aws_iam_policy_document" "ecs_logging_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = [
      aws_cloudwatch_log_group.lg.arn,
    ]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name_prefix        = var.names.role_prefix
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
}

resource "aws_iam_role_policy" "logging_permissions" {
  role = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_logging_permissions.json
}

resource "aws_iam_role_policy" "ecs_task_allow_internal_policy" {
  count       = var.code_artifact_policy == null ? 0 : 1
  role        = aws_iam_role.ecs_task_execution.id
  policy      = data.aws_iam_policy_document.ecs_task_allow.json
}

resource "aws_iam_role_policy" "ecs_task_allow_external_policy" {
  count       = var.code_artifact_policy != null ? 1 : 0
  role        = aws_iam_role.ecs_task_execution.id
  policy      = var.code_artifact_policy
}