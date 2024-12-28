
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

data "aws_iam_policy_document" "ecs_task_access" {
  statement {
    effect = "Allow"
    resources = ["*"]
    actions = ["sts:GetServiceBearerToken"]
    sid    = "AccessToCreateBearerToken"
    condition {
      test     = "StringEquals"
      values = ["codeartifact.amazonaws.com"]
      variable = "sts:AWSServiceName"
    }
  }

# TODO: Determine if these are necessary permissions
#   # Access to the domain
#   dynamic "statement" {
#     for_each = toset(local.unique_domains)
#     content {
#       effect = "Allow"
#       resources = [
#         "arn:aws:codeartifact:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:domain/${statement.value}"
#       ]
#       actions = ["codeartifact:*"]
#     }
#   }

  # Access to the repositories
  dynamic "statement" {
    for_each = toset(range(length(var.repositories)))
    content {
      effect = "Allow"
      resources = [
        "arn:aws:codeartifact:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:repository/${var.repositories[statement.value].domain}/${var.repositories[statement.value].domain}",
        "arn:aws:codeartifact:${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:repository/${var.repositories[statement.value].domain}/${var.repositories[statement.value].domain}/*"
      ]
      actions = ["codeartifact:*"]
    }
  }

  # Access to cloudwatch logs
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
      "${aws_cloudwatch_log_group.lg.arn}/*"
    ]
  }

  # Only created if anonymous access is not allowed
  dynamic "statement" {
    for_each = var.authentication.allow_anonymous ? [] : toset([0])
    content {
      effect  = "Allow"
      sid     = "AccessSecret"
      actions = ["secretsmanager:GetSecretValue"]
      resources = [
        aws_secretsmanager_secret.auth[0].arn
      ]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name_prefix        = var.names.role_prefix
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
}

resource "aws_iam_role_policy" "ecs_task_allow_internal_policy" {
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_access.json
}
