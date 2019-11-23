output "route53_bastion_public_fqdn" {
  description = "Route53 record for Bastion Host Load Balancer"
  value       = aws_route53_record.bastion-public.fqdn
}

output "route53_master-public-lb_public_fqdn" {
  description = "Route53 record for Master Public Load Balancer"
  value       = aws_route53_record.master_lb-public.fqdn
}