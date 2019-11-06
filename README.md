


<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| availability\_zones | Number of different AZs to use | number | `"3"` | no |
| aws\_profile | AWS cli profile (e.g. `default`) | string | `"default"` | no |
| aws\_region | AWS region (e.g. `us-east-1` => US North Virginia) | string | `"us-east-1"` | no |
| etcd\_instance\_type | EC2 instance type for the instances | string | `"t3.small"` | no |
| etcd\_instances | Number of EC2 instances to provision for etcd | number | `"3"` | no |
| hosted\_zone | Route53 Hosted Zone for creating records (without . suffix, e.g. `napo.io`) | string | n/a | yes |
| master\_instance\_type | EC2 instance type for the instances | string | `"t3.small"` | no |
| master\_instances | Number of EC2 instances to provision for Kubernetes master nodes | number | `"3"` | no |
| owner | Owner name used for tags | string | n/a | yes |
| project | Project name used for tags | string | `"k8s-the-real-hard-way"` | no |
| ssh\_public\_key\_path | SSH public key path | string | `"~/.ssh/id_rsa.pub"` | no |
| vpc\_cidr | VPC CIDR block | string | `"10.23.0.0/16"` | no |
| worker\_instance\_type | EC2 instance type for the instances | string | `"t3.small"` | no |
| worker\_instances | Number of EC2 instances to provision for Kubernetes worker nodes | number | `"3"` | no |

## Outputs

| Name | Description |
|------|-------------|
| route53\_etcd\_private\_fqdn | Route53 records for etcd instances private |
| route53\_etcd\_public\_fqdn | Route53 records for etcd instances public |
| route53\_master\_private\_fqdn | Route53 records for kube master instances private |
| route53\_master\_public\_fqdn | Route53 records for kube master instances public |
| route53\_worker\_private\_fqdn | Route53 records for kube worker instances private |
| route53\_worker\_public\_fqdn | Route53 records for kube worker instances public |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
