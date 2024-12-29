
resource "aws_lb" "this" {
  count = var.networking.load_balancer_arn == null ? 1 : 0

  name_prefix        = var.names.load_balancer_prefix
  internal           = true
  load_balancer_type = "application"
  security_groups    = local.security_groups
  subnets            = var.networking.subnets

  tags = merge({
    Name = var.names.load_balancer_prefix
  }, coalesce(var.tags.load_balancer, {}))

  depends_on = [aws_security_group.sg]
}

data "aws_lb" "this" {
  count = var.networking.load_balancer_arn == null ? 0 : 1
  arn   = var.networking.load_balancer_arn
}

locals {
  load_balancer_arn = coalesce(try(aws_lb.this[0].arn), var.networking.load_balancer_arn)
}

resource "aws_lb_target_group" "this" {
  name_prefix = var.names.load_balancer_target_group_prefix
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
    Name = var.names.load_balancer_prefix
  }, coalesce(var.tags.load_balancer_target_group, {}))

  depends_on = [aws_lb.this]
}

data "aws_route53_zone" "this" {
  count = length(var.repositories)
  name  = var.repositories[count.index].zone_name
}

resource "aws_route53_record" "this" {
  count = length(var.repositories)

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.repositories[count.index].hostname
  type    = "A"

  alias {
    name                   = var.networking.load_balancer_arn == null ? try(aws_lb.this[0].dns_name) : try(data.aws_lb.this[0].dns_name)
    zone_id                = var.networking.load_balancer_arn == null ? try(aws_lb.this[0].zone_id) : try(data.aws_lb.this[0].zone_id)
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "this" {
  count = length(var.repositories)

  domain_name       = aws_route53_record.this[count.index].name
  validation_method = "DNS"
}

resource "null_resource" "wait_for_certificate" {
  depends_on = [aws_acm_certificate.this]
}

resource "aws_route53_record" "cert_validation" {
  count = length(var.repositories)

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.this[count.index].zone_id
  name            = tolist(aws_acm_certificate.this[count.index].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.this[count.index].domain_validation_options)[0].resource_record_type
  ttl             = 300
  records         = [tolist(aws_acm_certificate.this[count.index].domain_validation_options)[0].resource_record_value]

  depends_on = [null_resource.wait_for_certificate]
}

resource "aws_acm_certificate_validation" "this" {
  count = length(var.repositories)

  certificate_arn         = aws_acm_certificate.this[count.index].arn
  validation_record_fqdns = aws_route53_record.cert_validation[*].fqdn
}

resource "aws_lb_listener" "this" {
  count             = length(var.repositories)
  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = aws_acm_certificate_validation.this[count.index].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}