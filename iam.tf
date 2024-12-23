
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

  statement {
    effect = "Allow"
    sid    = "AccessToCodeArtifactRepository"
    actions = [
      "codeartifact:*",
    ]
    resources = [
      "arn:aws:codeartifact:${local.codeartifact_region}:${local.codeartifact_account_id}:repository/${var.repository_settings.domain}/${var.repository_settings.repository}",
      "arn:aws:codeartifact:${local.codeartifact_region}:${local.codeartifact_account_id}:repository/${var.repository_settings.domain}/${var.repository_settings.repository}/*"
    ]
  }

  statement {
    effect  = "Allow"
    sid     = "AccessToCreateAuthToken"
    actions = ["codeartifact:GetAuthorizationToken"]
    resources = [
      "arn:aws:codeartifact:${local.codeartifact_region}:${local.codeartifact_account_id}:domain/${var.repository_settings.domain}",
    ]
  }

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

  statement {
    effect    = "Allow"
    resources = ["*"]
    actions   = ["sts:GetServiceBearerToken"]
    sid       = "AccessToCreateBearerToken"
    condition {
      test     = "StringEquals"
      values   = ["codeartifact.amazonaws.com"]
      variable = "sts:AWSServiceName"
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
  count  = var.codeartifact_policy == null ? 1 : 0
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_allow.json
}

resource "aws_iam_role_policy" "ecs_task_allow_external_policy" {
  count  = var.codeartifact_policy != null ? 1 : 0
  role   = aws_iam_role.ecs_task_execution.id
  policy = var.codeartifact_policy
}