output "route53_bastion_public_fqdn" {
  description = "Route53 record for Bastion Host instances"
  value       = aws_route53_record.bastion-public.fqdn
}