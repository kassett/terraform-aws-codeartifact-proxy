
resource "aws_lb" "this" {
  count = var.networking.load_balancer_arn == null ? 1 : 0

  name_prefix        = var.names.load_balancer
  internal           = true
  load_balancer_type = "application"
  security_groups    = local.security_groups
  subnets            = var.networking.subnets

  tags = merge({
    Name = var.names.load_balancer
  }, coalesce(var.tags.load_balancer, {}))

  depends_on = [aws_security_group.sg]
}

locals {
  load_balancer_arn = coalesce(try(aws_lb.this[0].arn), var.networking.load_balancer_arn)
}

resource "aws_lb_target_group" "this" {
  name_prefix = var.names.load_balancer_target_group
  port        = var.networking.container_port
  protocol    = "HTTP"
  vpc_id      = var.networking.vpc_id
  target_type = "ip"

  health_check {
    path                = var.networking.health_check.path
    interval            = var.networking.health_check.interval
    timeout             = var.networking.health_check.timeout
    healthy_threshold   = var.networking.health_check.healthy_threshold
    unhealthy_threshold = var.networking.health_check.unhealthy_threshold
  }

  tags = merge({
    Name = var.names.load_balancer_target_group
  }, coalesce(var.tags.load_balancer_target_group, {}))

  depends_on = [aws_lb.this]
}

data "aws_route53_zone" "this" {
  count = length(var.repositories)
  id  = var.repositories[count.index].zone_id
}

resource "aws_route53_record" "alias_record" {
  count = length(var.repositories)

  zone_id = data.aws_route53_zone.this[count.index].zone_id
  name    = var.repositories[count.index].hostname
  type    = "A"

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}

module "certificate" {
  count = length(var.repositories)

  source              = "terraform-aws-modules/acm/aws"

  domain_name         = var.repositories[count.index].hostname
  validation_method   = "DNS"
  validate_certificate = true

  create_route53_records = true
  validation_record_fqdns = [aws_route53_record.alias_record[count.index].fqdn]

  depends_on = [aws_route53_record.alias_record]
}

resource "aws_lb_listener" "this" {
  count = length(var.repositories)
  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = module.certificate[count.index].acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}