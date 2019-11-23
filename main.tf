# Data sources
## Ubuntu AMI for all K8s instances
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
}

## Amazon Linux AMI for Bastion Host
data "aws_ami" "amazonlinux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

}

## AWS region's Availabililty Zones
data "aws_availability_zones" "available" {
  state = "available"
}

## Get local workstation's external IPv4 address
data "http" "workstation-external-ip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  workstation-external-cidr = "${chomp(data.http.workstation-external-ip.body)}/32"
}

## Route53 HostedZone ID from name
data "aws_route53_zone" "selected" {
  name         = "${var.hosted_zone}."
  private_zone = false
}

# AWS VPC
resource "aws_vpc" "main" {
  cidr_block                       = var.aws_vpc_cidr
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = false

  tags = {
    Name    = "${var.project}-vpc"
    Project = var.project
    Owner   = var.owner
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count             = var.availability_zones
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 11)
  tags = {
    Name      = "${var.project}-public-${count.index}"
    Attribute = "public"
    Project   = var.project
    Owner     = var.owner
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count                   = var.availability_zones
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 1)
  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.project}-private-${count.index}"
    Attribute = "private"
    Project   = var.project
    Owner     = var.owner
  }
}

# AWS Elastic IP addresses (EIP) for NAT Gateways
resource "aws_eip" "nat" {
  count = var.availability_zones

  vpc = true

  tags = {
    Name    = "${var.project}-eip-natgw-${count.index}"
    Project = var.project
    Owner   = var.owner
  }
}

# AWS NAT Gateways
resource "aws_nat_gateway" "natgw" {
  count = var.availability_zones

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = element(aws_subnet.public.*.id, count.index)

  tags = {
    Name    = "${var.project}-natgw-${count.index}"
    Project = var.project
    Owner   = var.owner
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-igw"
    Project = var.project
    Owner   = var.owner
  }
}

# AWS Route Tables
## Public
resource "aws_route_table" "rt-public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name      = "${var.project}-rt-public"
    Attribute = "public"
    Project   = var.project
    Owner     = var.owner
  }
}

## Private
resource "aws_route_table" "rt-private" {
  count  = var.availability_zones
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw[count.index].id
  }

  tags = {
    Name      = "${var.project}-rt-private"
    Attribute = "private"
    Project   = var.project
    Owner     = var.owner
  }
}


# AWS Route Table Associations
## Public
resource "aws_route_table_association" "public-rtassoc" {
  count          = var.availability_zones
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.rt-public.id
}

## Private
resource "aws_route_table_association" "private-rtassoc" {
  count          = var.availability_zones
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.rt-private[count.index].id
}

# AWS Key Pair to generate
# => If you want to use an existing AWS Key Pair one, set value for TF var.aws_key_pair_name
resource "aws_key_pair" "ssh" {
  count      = var.aws_key_pair_name != null ? 1 : 0
  key_name   = "${var.owner}-${var.project}"
  public_key = file(var.ssh_public_key_path)
}

# IAM Roles for EC2 Instance Profiles
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

## Bastion Host
data "aws_iam_policy_document" "bastion" {
  statement {
    sid = "bastion"
    actions = [
      "autoscaling:DescribeAutoScalingInstances",
      "ec2:CreateRoute",
      "ec2:CreateTags",
      "ec2:DescribeAutoScalingGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers",
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }

  statement {
    sid = "route53"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${data.aws_route53_zone.selected.zone_id}"
    ]
  }
}

resource "aws_iam_role" "bastion" {
  name_prefix        = "bastion-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name    = "${var.project}-bastion"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy" "bastion" {
  name_prefix = "bastion-"
  role        = aws_iam_role.bastion.id
  policy      = data.aws_iam_policy_document.bastion.json
}

resource "aws_iam_instance_profile" "bastion" {
  name_prefix = "bastion-"
  role        = aws_iam_role.bastion.name
}

## etcd & Kubernetes instances
data "aws_iam_policy_document" "etcd_worker_master" {
  statement {
    sid = "autoscaling"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "etcd_worker_master" {
  name_prefix = "etcd-worker-master-"

  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name    = "${var.project}-etcd-worker-master"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy" "etcd_worker_master" {
  name_prefix = "etcd-worker-master-"
  role        = aws_iam_role.etcd_worker_master.id
  policy      = data.aws_iam_policy_document.etcd_worker_master.json
}

resource "aws_iam_instance_profile" "etcd_worker_master" {
  name_prefix = "etcd-worker-master-"
  role        = aws_iam_role.etcd_worker_master.name
}


# SecurityGroups
resource "aws_security_group" "bastion-lb" {
  name_prefix = "bastion-lb-"
  description = "Bastion-LB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-bastion-lb"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "master-public-lb" {
  name_prefix = "master-public-lb-"
  description = "Master-Public-LB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-master-lb-public"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "master-private-lb" {
  name_prefix = "master-private-lb-"
  description = "Master-Private-LB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-master-lb-private"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "bastion-"
  description = "Bastion"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-bastion"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "etcd" {
  name_prefix = "etcd-"
  description = "etcd"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-etcd"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "master" {
  name_prefix = "k8s-master-"
  description = "K8s Master"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-k8s-master"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "worker" {
  name_prefix = "k8s-worker-"
  description = "K8s Worker"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-k8s-worker"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}


# Security Group rules to add to above SecurityGroups
## Ingress
resource "aws_security_group_rule" "ssh" {
  for_each = {
    "Etcd"    = aws_security_group.etcd.id,
    "Masters" = aws_security_group.master.id,
    "Workers" = aws_security_group.worker.id,
  }
  security_group_id        = each.value
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  description              = "SSH: Bastion - ${each.key}"
}

### Bastion Host
resource "aws_security_group_rule" "allow_ingress_on_bastion_kubectl" {
  for_each = {
    "MasterPrivateLB" = aws_security_group.master-private-lb.id,
    "Masters"         = aws_security_group.master.id,
    "Workers"         = aws_security_group.worker.id
  }
  security_group_id        = each.value
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  description              = "kubectl: Bastion - ${each.key}"
}

resource "aws_security_group_rule" "allow_ingress_bastion-lb_on_bastion_ssh" {
  security_group_id        = aws_security_group.bastion.id
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion-lb.id
  description              = "SSH: Bastion-LB - Bastion"
}

### Bastion LB
resource "aws_security_group_rule" "allow_ingress_workstation_on_bastion-lb_ssh" {
  security_group_id = aws_security_group.bastion-lb.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [local.workstation-external-cidr]
  description       = "SSH: Workstation - MasterPublicLB"
}

### MasterPublicLB
resource "aws_security_group_rule" "allow_ingress_workstation_on-master-public-lb_kubectl" {
  security_group_id = aws_security_group.master-public-lb.id
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [local.workstation-external-cidr]
  description       = "kubectl: Workstation - MasterPublicLB"
}

### MasterPrivateLB
resource "aws_security_group_rule" "allow_ingress_on_master-private-lb_kubeapi" {
  security_group_id = aws_security_group.master-private-lb
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "kubeapi: ALL - MasterPrivateLB"
}

### etcd
resource "aws_security_group_rule" "allow_etcd" {
  for_each = {
    "Masters" = aws_security_group.master.id,
    "Etcd"    = aws_security_group.etcd.id
  }
  security_group_id        = aws_security_group.etcd.id
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2380
  protocol                 = "tcp"
  source_security_group_id = each.value
  description              = "etcd: ${each.key} - Etcds"
}

### Master
resource "aws_security_group_rule" "allow_kubectl_on_master" {
  for_each = {
    "MasterPublicLB"  = aws_security_group.master-public-lb.id,
    "MasterPrivateLB" = aws_security_group.master-private-lb.id,
    "Workers"         = aws_security_group.worker.id
  }
  security_group_id        = aws_security_group.master.id
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  source_security_group_id = each.value
  description              = "kubectl: ${each.key} - Masters"
}

resource "aws_security_group_rule" "allow_ingress_worker_on_master_all" {
  security_group_id        = aws_security_group.master.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "all"
  source_security_group_id = aws_security_group.worker.id
  description              = "ALL: Workers - Masters"
}

### Worker
resource "aws_security_group_rule" "allow_ingress_on_worker_all" {
  for_each = {
    "Masters"         = aws_security_group.master.id,
    "MasterPrivateLB" = aws_security_group.master-private-lb.id
  }
  security_group_id        = aws_security_group.worker.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "all"
  source_security_group_id = each.value
  description              = "ALL: ${each.key} - Workers"
}

## Egress
resource "aws_security_group_rule" "egress_all" {
  for_each = {
    "BastionLB"       = aws_security_group.bastion-lb.id,
    "MasterPublicLB"  = aws_security_group.master-public-lb.id,
    "MasterPrivateLB" = aws_security_group.master-private-lb.id,
    "Bastion"         = aws_security_group.bastion.id,
    "Etcds"           = aws_security_group.etcd.id,
    "Masters"         = aws_security_group.master.id,
    "Workers"         = aws_security_group.worker.id
  }
  security_group_id = each.value
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Egress ALL: ${each.key}"
}

# Load Balancer
## Bastion Host
resource "aws_elb" "bastion" {
  name_prefix     = "basti-" // cannot be longer than 6 characters
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.bastion-lb.id]

  listener {
    instance_port     = 22
    instance_protocol = "tcp"
    lb_port           = 22
    lb_protocol       = "tcp"
  }

  tags = {
    Name    = "${var.project}-bastion-lb"
    Project = var.project
    Owner   = var.owner
  }
}

## Kubernetes Master (for remote kubctl access from workstation)
resource "aws_elb" "master-public" {
  name_prefix     = "master" // cannot be longer than 6 characters
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.master-public-lb.id]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  tags = {
    Name      = "${var.project}-master--publiclb"
    Attribute = "public"
    Project   = var.project
    Owner     = var.owner
  }
}

## Kubernetes Master (fronting kube-apiservers)
resource "aws_elb" "master-private" {
  name_prefix     = "master" // will be prefixed with internal -  cannot be longer than 6 characters
  internal        = true
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.master-private-lb.id]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  tags = {
    Name     = "${var.project}-master--private-lb"
    ttribute = "private"
    Project  = var.project
    Owner    = var.owner
  }
}

# LaunchConfigurations
## Bastion Host
resource "aws_launch_configuration" "bastion" {
  name_prefix                 = "bastion-"
  image_id                    = data.aws_ami.amazonlinux.id
  instance_type               = var.bastion_instance_type
  security_groups             = [aws_security_group.bastion.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = false
  ebs_optimized               = true
  enable_monitoring           = true
  iam_instance_profile        = aws_iam_instance_profile.bastion.id

  user_data = templatefile("${path.module}/userdata-bastion.tpl", {
    component = "bastion"
    domain    = var.hosted_zone
  })

  lifecycle {
    create_before_destroy = true
  }
}

## etcd
resource "aws_launch_configuration" "etcd" {
  name_prefix                 = "etcd-"
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.etcd_instance_type
  security_groups             = [aws_security_group.etcd.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = false
  ebs_optimized               = true
  enable_monitoring           = true
  iam_instance_profile        = aws_iam_instance_profile.etcd_worker_master.id

  user_data = templatefile("${path.module}/userdata.tpl", {
    domain = var.hosted_zone
  })

  lifecycle {
    create_before_destroy = true
  }
}

## Kubernetes Master
resource "aws_launch_configuration" "master" {
  name_prefix                 = "master-"
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.master_instance_type
  security_groups             = [aws_security_group.master.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = false
  ebs_optimized               = true
  enable_monitoring           = true
  iam_instance_profile        = aws_iam_instance_profile.etcd_worker_master.id

  user_data = templatefile("${path.module}/userdata.tpl", {
    domain = var.hosted_zone
  })

  lifecycle {
    create_before_destroy = true
  }
}

## Kubernetes Worker
resource "aws_launch_configuration" "worker" {
  name_prefix                 = "worker-"
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  security_groups             = [aws_security_group.worker.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = false
  ebs_optimized               = true
  enable_monitoring           = true
  iam_instance_profile        = aws_iam_instance_profile.etcd_worker_master.id

  user_data = templatefile("${path.module}/userdata-worker.tpl", {
    pod_cidr = var.pod_cidr
    domain   = var.hosted_zone
  })

  lifecycle {
    create_before_destroy = true
  }
}


# AutoScalingGroups
## Bastion
resource "aws_autoscaling_group" "bastion" {
  max_size             = var.bastion_max_size
  min_size             = var.bastion_min_size
  desired_capacity     = var.bastion_size
  force_delete         = false
  launch_configuration = aws_launch_configuration.bastion.name
  vpc_zone_identifier  = aws_subnet.private.*.id
  load_balancers       = [aws_elb.bastion.id]

  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-bastion"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = true
    }
  ]
}

## etcd
resource "aws_autoscaling_group" "etcd" {
  max_size             = var.etcd_max_size
  min_size             = var.etcd_min_size
  desired_capacity     = var.etcd_size
  force_delete         = true
  launch_configuration = aws_launch_configuration.etcd.name
  vpc_zone_identifier  = aws_subnet.private.*.id

  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-etcd"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = true
    }
  ]
}

## Kubernetes Master
resource "aws_autoscaling_group" "master" {
  max_size             = var.master_max_size
  min_size             = var.master_min_size
  desired_capacity     = var.master_size
  force_delete         = true
  launch_configuration = aws_launch_configuration.master.name
  vpc_zone_identifier  = aws_subnet.private.*.id
  load_balancers       = [aws_elb.master-public.id, aws_elb.master-private.id]

  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-k8s-master"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = true
    }
  ]
}

## Kubernetes Worker
resource "aws_autoscaling_group" "worker" {
  max_size             = var.worker_max_size
  min_size             = var.worker_min_size
  desired_capacity     = var.worker_size
  force_delete         = true
  launch_configuration = aws_launch_configuration.worker.name
  vpc_zone_identifier  = aws_subnet.private.*.id

  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-k8s-worker"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = var.owner
      propagate_at_launch = true
    }
  ]
}


# Route53
## Bastion Host
resource "aws_route53_record" "bastion-public" {
  zone_id = data.aws_route53_zone.selected.id
  name    = "bastion"
  type    = "A"

  alias {
    evaluate_target_health = false
    name                   = aws_elb.bastion.dns_name
    zone_id                = aws_elb.bastion.zone_id
  }
}

## Kubernetes Master for remote kubectl access
resource "aws_route53_record" "master_lb-public" {
  zone_id = data.aws_route53_zone.selected.id
  name    = "kube"
  type    = "A"

  alias {
    evaluate_target_health = false
    name                   = aws_elb.master-public.dns_name
    zone_id                = aws_elb.master-public.zone_id
  }
}
