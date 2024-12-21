
data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

locals {
  region = coalesce(var.codeartifact_region, data.aws_region.this.name)
  account_id = coalesce(var.codeartifact_account_id, data.aws_caller_identity.this.account_id)
}

resource "aws_ecs_cluster" "cluster" {
  count = var.create_cluster ? 1 : 0
  name = var.cluster_name
  tags = var.cluster_tags
}

resource "aws_ecs_task_definition" "td" {

}