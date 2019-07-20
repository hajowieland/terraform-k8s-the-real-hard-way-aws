output "route53_worker_fqdn" {
  description = "Route53 records for worker instances"
  value       = [aws_route53_record.worker.*.fqdn]
}

output "route53_master_fqdn" {
  description = "Route53 records for master instances"
  value       = [aws_route53_record.master.*.fqdn]
}

output "elastic_ip_master" {
  description = "Elastic IP for first master node"
  value       = [aws_eip.eip.public_ip]
}