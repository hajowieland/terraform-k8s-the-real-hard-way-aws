# Terraform - Kubernetes The (real) Hard Way on AWS!

This little project creates the infrastructure in Terraform for my blog post [Kubernetes The (real) Hard Way on AWS](https://napo.io/posts/kubernetes-the-real-hard-way-on-aws/).

> AWS CDK Python code available 🔗 [HERE](https://github.com/hajowieland/cdk-py-k8s-the-real-hard-way-aws)


You can practice creating a multi node K8s Cluster yourself for training purposes or CKA exam preparation.


![Alt text](terraform-k8s-real-hard-way.png?raw=true "Infrastructure Diagram")

## Requirements

* aws-cli Profile
* Existing AWS Route53 Public Hosted Zone

## Features

_Default values - you can adapt all of them to your needs_

* Terraform 0.12
* 1x VPC, 3x Public Subnets, 3x Private Subnets, Route Tables, Routes
* 3x Worker Nodes
* 3x Master Nodes
* 3x Etcd Nodes
* 1x Bastion Host
* Genertes AWS Key Pair for instances
* Route53 Records for internal & external IPv4 addresses
* 1x Public LoadBalancer for Master Nodes (external kubectl access)
* 1x Private LoadBalancer for Master Nodes (fronting kube-apiservers)
* 1x Public LoadBalancer for Bation Host (AutoScalingGroup)
* Gets most recent Ubuntu AMI for all regions
* Install awscli, cfssl, cfssl_json via UserData
* Allows external access from workstation IPv4 address only


<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| availability\_zones | Number of different AZs to use | number | `"3"` | no |
| aws\_key\_pair\_name | AWS Key Pair name to use for EC2 Instances (if already existent) | string | `"null"` | no |
| aws\_profile | AWS cli profile (e.g. `default`) | string | `"default"` | no |
| aws\_region | AWS region (e.g. `us-east-1` => US North Virginia) | string | `"us-east-1"` | no |
| aws\_vpc\_cidr | VPC CIDR block | string | `"10.23.0.0/16"` | no |
| bastion\_instance\_type | EC2 instance type for Bastion Host | string | `"t3a.small"` | no |
| bastion\_max\_size | Maximum number of EC2 instances for Bastion AutoScalingGroup | number | `"1"` | no |
| bastion\_min\_size | Minimum number of EC2 instances for Bastion AutoScalingGroup | number | `"1"` | no |
| bastion\_size | Desired number of EC2 instances for Bastion AutoScalingGroup | number | `"1"` | no |
| etcd\_instance\_type | EC2 instance type for etcd instances | string | `"t3a.small"` | no |
| etcd\_max\_size | Maximum number of EC2 instances for etcd AutoScalingGroup | number | `"3"` | no |
| etcd\_min\_size | Minimum number of EC2 instances for etcd AutoScalingGroup | number | `"3"` | no |
| etcd\_size | Desired number of EC2 instances for etcd AutoScalingGroup | number | `"3"` | no |
| hosted\_zone | Route53 Hosted Zone for creating records (without . suffix, e.g. `napo.io`) | string | n/a | yes |
| master\_instance\_type | EC2 instance type for K8s master instances | string | `"t3a.small"` | no |
| master\_max\_size | Maximum number of EC2 instances for K8s Master AutoScalingGroup | number | `"3"` | no |
| master\_min\_size | Minimum number of EC2 instances for K8s Master AutoScalingGroup | number | `"3"` | no |
| master\_size | Desired number of EC2 instances for K8s Master AutoScalingGroup | number | `"3"` | no |
| owner | Owner name used for tags | string | `"napo.io"` | no |
| pod\_cidr | The first two octets for the Pod network CIDR (used in Worker UserData to generate POD_CIDR envvar) | string | `"10.200"` | no |
| project | Project name used for tags | string | `"k8s-the-right-hard-way-aws"` | no |
| ssh\_public\_key\_path | SSH public key path (to create a new AWS Key Pair from existing local SSH public RSA key) | string | `"~/.ssh/id_rsa.pub"` | no |
| stage | Environment name (e.g. `testing`, `dev`, `staging`, `prod`) | string | `"testing"` | no |
| worker\_instance\_type | EC2 instance type for K8s worker instances | string | `"t3a.small"` | no |
| worker\_max\_size | Maximum number of EC2 instances for K8s Worker AutoScalingGroup | number | `"3"` | no |
| worker\_min\_size | Minimum number of EC2 instances for K8s Worker AutoScalingGroup | number | `"3"` | no |
| worker\_size | Desired number of EC2 instances for K8s Worker AutoScalingGroup | number | `"3"` | no |

## Outputs

| Name | Description |
|------|-------------|
| route53\_bastion\_public\_fqdn | Route53 record for Bastion Host Load Balancer |
| route53\_master-public-lb\_public\_fqdn | Route53 record for Master Public Load Balancer |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
