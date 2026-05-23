# public hosted zone

data "aws_route53_zone" "app" {
  name         = var.domain
  private_zone = false
}


# dns recrod from domain to alb


# dns route53 record -> ALB DNS name
resource "aws_route53_record" "app_record" {
  zone_id = data.aws_route53_zone.app.zone_id
  name    = "2tierapp.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_alb.app.dns_name
    zone_id                = aws_alb.app.zone_id
    evaluate_target_health = true
  }
}

# ACM certificate for ALB
resource "aws_acm_certificate" "app_cert" {
  domain_name       = "2tierapp.${var.domain}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation record
resource "aws_route53_record" "cert_validation" {
  for_each = { for dvo in aws_acm_certificate.app_cert.domain_validation_options : dvo.domain_name => {
    name   = dvo.resource_record_name
    type   = dvo.resource_record_type
    record = dvo.resource_record_value
  } }

  zone_id = data.aws_route53_zone.app.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}