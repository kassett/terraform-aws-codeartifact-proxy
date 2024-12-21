
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
  statement = {
    effect  = "Allow"
    actions = ["codeartifact:*"]
    resources = [
      "arn:aws:codeartifact:${local.region}:${local.account_id}:repository/${var.codeartifact_domain}/${var.codeartifact_repository}",
      "arn:aws:codeartifact:${local.region}:${local.account_id}:repository/${var.codeartifact_domain}/${var.codeartifact_repository}/*"
    ]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name_prefix        = var.ecs_task_role_prefix
  assume_role_policy = data.aws_iam_policy
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_tailscale" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_allow_internal_policy" {
  count       = var.code_artifact_policy == null ? 0 : 1
  name_prefix = "${var.ecs_task_role_prefix}Policy"
  role        = aws_iam_role.ecs_task_execution.id
  policy      = data.aws_iam_policy_document.ecs_task_allow.json
}

resource "aws_iam_role_policy" "ecs_task_allow_external_policy" {
  count       = var.code_artifact_policy == null ? 1 : 0
  name_prefix = "${var.ecs_task_role_prefix}Policy"
  role        = aws_iam_role.ecs_task_execution.id
  policy      = var.code_artifact_policy
}