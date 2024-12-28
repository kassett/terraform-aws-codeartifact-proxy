
output "load_balancer_dns_name" {
  value = try(aws_lb.this[0].dns_name)
}

output "load_balancer_arn" {
  value = try(aws_lb.this[0].arn)
}

output "load_balancer_name" {
  value = try(aws_lb.this[0].name)
}

output "load_balancer_zone_id" {
  value = try(aws_lb.this[0].zone_id)
}