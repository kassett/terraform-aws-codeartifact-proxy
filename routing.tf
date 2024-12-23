
resource "aws_lb" "this" {
  count = var.hosting != null ? 1 : 0

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

resource "aws_lb_target_group" "this" {
  count = var.hosting != null ? 1 : 0

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
  count = var.hosting != null ? 1 : 0
  name  = var.hosting.zone_name
}

resource "aws_route53_record" "this" {
  count = var.hosting != null ? 1 : 0

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = "${var.hosting.record_name}.${var.hosting.zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "this" {
  count = var.hosting != null ? 1 : 0

  domain_name       = "${var.hosting.record_name}.${var.hosting.zone_name}"
  validation_method = "DNS"
}

resource "null_resource" "wait_for_certificate" {
  depends_on = [aws_acm_certificate.this]
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in coalesce(
      try(aws_acm_certificate.this[0].domain_validation_options, []),
      []
    ) : dvo.domain_name => dvo
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  ttl             = 300
  records         = [each.value.resource_record_value]

  depends_on = [null_resource.wait_for_certificate]
}

resource "aws_acm_certificate_validation" "this" {
  count = var.hosting != null ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# module "acm" {
#   count = var.hosting != null ? 1 : 0
#
#   source = "terraform-aws-modules/acm/aws"
#
#   domain_name          = "${var.hosting.record_name}.${var.hosting.zone_name}"
#   zone_id              = data.aws_route53_zone.this[0].zone_id
#   validate_certificate = true
#   validation_method    = "DNS"
#   wait_for_validation = true
# }

resource "aws_lb_listener" "this" {
  count = var.hosting != null ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.hosting.ssl_policy
  certificate_arn   = aws_acm_certificate_validation.this[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}
