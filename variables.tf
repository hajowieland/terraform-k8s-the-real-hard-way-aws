variable "aws_region" {
  description = "AWS region (e.g. `us-east-1` => US North Virginia)"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS cli profile (e.g. `default`)"
  type        = string
  default     = "default"
}

variable "availability_zones" {
  description = "Number of different AZs to use"
  type        = number
  default     = 3
}

variable "etcd_instances" {
  description = "Number of EC2 instances to provision for etcd"
  type        = number
  default     = 3
}

variable "master_instances" {
  description = "Number of EC2 instances to provision for Kubernetes master nodes"
  type        = number
  default     = 3
}

variable "worker_instances" {
  description = "Number of EC2 instances to provision for Kubernetes worker nodes"
  type        = number
  default     = 3
}

variable "etcd_instance_type" {
  description = "EC2 instance type for the instances"
  type        = string
  default     = "t3.small"
}

variable "master_instance_type" {
  description = "EC2 instance type for the instances"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "EC2 instance type for the instances"
  type        = string
  default     = "t3.small"
}

variable "project" {
  description = "Project name used for tags"
  type        = string
  default     = "k8s-hard-way"
}

variable "owner" {
  description = "Owner name used for tags"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.23.0.0/16"
}

variable "ssh_public_key_path" {
  description = "SSH public key path"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "hosted_zone" {
  description = "Route53 Hosted Zone for creating records (without . suffix, e.g. `example.com`)"
  type        = string
}