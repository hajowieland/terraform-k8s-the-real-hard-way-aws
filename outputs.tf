output "route53_etcd_public_fqdn" {
  description = "Route53 records for etcd instances public"
  value       = [aws_route53_record.etcd-public.*.fqdn]
}

output "route53_etcd_private_fqdn" {
  description = "Route53 records for etcd instances private"
  value       = [aws_route53_record.etcd-private.*.fqdn]
}

output "route53_master_public_fqdn" {
  description = "Route53 records for kube master instances public"
  value       = [aws_route53_record.master-public.*.fqdn]
}

output "route53_master_private_fqdn" {
  description = "Route53 records for kube master instances private"
  value       = [aws_route53_record.master-private.*.fqdn]
}

output "route53_worker_public_fqdn" {
  description = "Route53 records for kube worker instances public"
  value       = [aws_route53_record.worker-public.*.fqdn]
}

output "route53_worker_private_fqdn" {
  description = "Route53 records for kube worker instances private"
  value       = [aws_route53_record.worker-private.*.fqdn]
}
