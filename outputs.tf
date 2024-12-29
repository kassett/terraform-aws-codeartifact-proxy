
output "cluster_arn" {
  value = try(aws_ecs_cluster.cluster[0].arn, null)
}

output "cluster_name" {
  value = try(aws_ecs_cluster.cluster[0].name, null)
}

output "cluster_id" {
  value = try(aws_ecs_cluster.cluster[0].id, null)
}

output "service_name" {
  value = aws_ecs_service.this.name
}

output "service_id" {
  value = aws_ecs_service.this.id
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_definition_arn_without_revision" {
  value = aws_ecs_task_definition.this.arn_without_revision
}

output "task_definition_id" {
  value = aws_ecs_task_definition.this.id
}

output "security_group_ids" {
  value = aws_ecs_service.this.network_configuration.security_groups
}

output "subnets" {
  value = aws_ecs_service.this.network_configuration.subnets
}

output "load_balancer_arn" {
  value = coalesce(var.networking.load_balancer_arn, try(aws_lb.this[0].arn))
}

output "load_balancer_name" {
  value = var.networking.load_balancer_arn != null ? try(data.aws_lb.this[0].name, null) : try(aws_lb.this[0].name, null)
}

output "lb_listener_arn_map" {
  value = { for i in range(var.repositories) : var.repositories[i].hostname => aws_lb_listener.this[i].arn }
}

output "certificate_arn_map" {
  value = { for i in range(var.repositories) : var.repositories[i].hostname => aws_acm_certificate_validation.this[i].certificate_arn }
}