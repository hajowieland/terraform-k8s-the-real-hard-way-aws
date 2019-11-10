# Data sources
## Get most recent Ubuntu AMI for all nodes execept Bastion
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

## Get all ready AWS region's Availabililty Zones
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

## Get HostedZone ID
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
  #cidr_block        = cidrsubnet(var.aws_vpc_cidr, 4, 1 + (1 * var.availability_zones) + count.index)
  cidr_block = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 11)
  tags = {
    Name    = "${var.project}-public-${count.index}"
    Project = var.project
    Owner   = var.owner
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = var.availability_zones
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id
  #cidr_block              = cidrsubnet(var.aws_vpc_cidr, 4, 1 + (2 * var.availability_zones) + count.index)
  cidr_block              = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 1)
  map_public_ip_on_launch = false

  tags = {
    Name    = "${var.project}-private-${count.index}"
    Project = var.project
    Owner   = var.owner
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

  tags = {
    Name    = "${var.project}-rt-public"
    Project = var.project
    Owner   = var.owner
  }
}

resource "aws_route" "route-igw" {
  count                  = var.availability_zones
  route_table_id         = aws_route_table.rt-public.id
  gateway_id             = aws_internet_gateway.igw.id
  destination_cidr_block = "0.0.0.0/0"

  depends_on = [aws_route_table.rt-public]
}

## Private
resource "aws_route_table" "rt-private" {
  count = var.availability_zones

  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-rt-private"
    Project = var.project
    Owner   = var.owner
  }
}

resource "aws_route" "route-nat" {
  count                  = var.availability_zones
  route_table_id         = aws_route_table.rt-private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgw[count.index].id

  depends_on = [aws_route_table.rt-private]
}

//resource "aws_route" "route-pod-cidr" {
//  count                  = var.availability_zones
//  route_table_id         = aws_route_table.rt-private[count.index].id
//  destination_cidr_block = "0.0.0.0/0"
//  nat_gateway_id         = aws_nat_gateway.natgw[count.index].id
//  depends_on             = [aws_route_table.rt-private]
//}

# AWS Route Table Associations
## Public
resource "aws_route_table_association" "public-rtassoc" {
  count          = var.availability_zones
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.rt-public.id
}

## Private
resource "aws_route_table_association" "private-rtassoc" {
  count = var.availability_zones

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.rt-private[count.index].id
}


# ENIs for Kubernetes Worker nodes
resource "aws_network_interface" "enis" {
  count       = var.worker_max_size
  subnet_id   = element(aws_subnet.private.*.id, count.index % var.availability_zones)
  private_ips = [cidrhost(element(aws_subnet.private.*.cidr_block, count.index % var.availability_zones), 100)]
}


# AWS Key Pair to generate
# => If you want to use an existing AWS Key Pair one, set value for TF var.aws_key_pair_name
resource "aws_key_pair" "ssh" {
  count = var.aws_key_pair_name != null ? 1 : 0
  #key_name   = "${var.owner}-key"
  key_name   = "id_rsa-hajoventx"
  public_key = file(var.ssh_public_key_path)
}

# IAM Roles for Instance Profiles
resource "aws_iam_role" "bastion" {
  name_prefix = "bastion-"

  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role.json

  tags = {
    Name    = "${var.project}-bastion"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "ec2-assume-role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "bastion" {
  statement {
    sid = "autoscaling"
    actions = [
      "ec2:CreateRoute",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "bastion" {
  name_prefix = "bastion-"
  role        = aws_iam_role.bastion.id
  policy      = data.aws_iam_policy_document.bastion.json
}

# IAM EC2 Instance Profile
resource "aws_iam_instance_profile" "bastion" {
  name_prefix = "bastion-"
  role        = aws_iam_role.bastion.name
}

## Bastion Host
resource "aws_iam_role" "etcd-worker-master" {
  name_prefix = "etcd-worker-master-"

  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role.json

  tags = {
    Name    = "${var.project}-etcd-worker-master"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "etcd-worker-master" {
  statement {
    sid = "autoscaling"
    actions = [
      "ec2:AttachNetworkInterface",
      "ec2:CreateNetworkInterface",
      "ec2:CreateRoute",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "etcd-worker-master" {
  name_prefix = "etcd-worker-master-"
  role        = aws_iam_role.etcd-worker-master.id
  policy      = data.aws_iam_policy_document.etcd-worker-master.json
}

resource "aws_iam_instance_profile" "etcd-worker-master" {
  name_prefix = "etcd-worker-master-"
  role        = aws_iam_role.etcd-worker-master.name
}

# SecurityGroups
resource "aws_security_group" "bastion-lb" {
  name        = "allow_workstation_ssh"
  description = "Allow SSH inbound traffic from Workstation"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-bastionlb-workstation"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "master-lb" {
  name        = "allow_workstation_kubectl"
  description = "Allow kube-api kubectl inbound traffic from Workstation"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project}-masterlb-workstation"
    Project = var.project
    Owner   = var.owner
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "bastion" {
  name_prefix = "bastion-"
  description = "bastion"
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
  name_prefix = "k8s_master-"
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
  name_prefix = "k8s_worker-"
  description = "K8s Master"
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
resource "aws_security_group_rule" "allow-ingress-bastion_lb-on-bastion-ssh" {
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion.id
  to_port                  = 22
  type                     = "ingress"
  source_security_group_id = aws_security_group.bastion-lb.id
}

resource "aws_security_group_rule" "allow-ingress-workstation-on-bastion_lb-ssh" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion-lb.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = [local.workstation-external-cidr]
}

resource "aws_security_group_rule" "allow-ingress-workstation-on-master_lb-kubectl" {
  from_port         = 6443
  protocol          = "tcp"
  security_group_id = aws_security_group.master-lb.id
  to_port           = 6443
  type              = "ingress"
  cidr_blocks       = [local.workstation-external-cidr]
}

resource "aws_security_group_rule" "allow-ingress-master_lb-on-master-kubectl" {
  from_port                = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.master.id
  to_port                  = 6443
  type                     = "ingress"
  source_security_group_id = aws_security_group.master-lb.id
}

resource "aws_security_group_rule" "allow-ingress-bastion-on-worker-ssh" {
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  to_port                  = 22
  type                     = "ingress"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "allow-ingress-bastion-on-worker-kubectl" {
  from_port                = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker.id
  to_port                  = 6443
  type                     = "ingress"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "allow-ingress-bastion-on-etcd-ssh" {
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.etcd.id
  to_port                  = 22
  type                     = "ingress"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "allow-ingress-master-on-etcd-etcd" {
  from_port                = 2379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.etcd.id
  to_port                  = 2380
  type                     = "ingress"
  source_security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "allow-ingress-worker-on-master-all" {
  from_port                = 0
  protocol                 = "all"
  security_group_id        = aws_security_group.master.id
  to_port                  = 65535
  type                     = "ingress"
  source_security_group_id = aws_security_group.worker.id
}

resource "aws_security_group_rule" "allow-ingress-bastion-on-master-ssh" {
  from_port                = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.master.id
  to_port                  = 22
  type                     = "ingress"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "allow-ingress-worker-on-master-kubectl" {
  from_port                = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.master.id
  to_port                  = 6443
  type                     = "ingress"
  source_security_group_id = aws_security_group.bastion.id
}


resource "aws_security_group_rule" "allow-ingress-master-on-worker-all" {
  from_port                = 0
  protocol                 = "all"
  security_group_id        = aws_security_group.worker.id
  to_port                  = 65535
  type                     = "ingress"
  source_security_group_id = aws_security_group.master.id
}

resource "aws_security_group_rule" "allow-egress-on-bastion-all" {
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.bastion.id
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow-egress-on-bastion_lb-all" {
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.bastion-lb.id
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow-egress-on-master_lb-all" {
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.master-lb.id
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow-egress-on-etcd-all" {
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.etcd.id
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow-egress-on-master-all" {
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.master.id
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow-egress-on-worker-all" {
  from_port         = 0
  to_port           = 0
  security_group_id = aws_security_group.worker.id
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
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

## Kubernetes Master (fronting kube-apiservers, for remote kubctl access from workstation)
resource "aws_elb" "master" {
  name_prefix     = "master"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.master-lb.id]

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  tags = {
    Name    = "${var.project}-master-lb"
    Project = var.project
    Owner   = var.owner
  }
}

# LaunchTemplates
## BastionHost
//resource "aws_launch_template" "worker" {
//  name_prefix = "worker-"
//
//  ebs_optimized = true
//
//  iam_instance_profile {
//    name = aws_iam_instance_profile.etcd-worker-master.name
//  }
//
//  image_id = data.aws_ami.ubuntu.id
//  instance_type = var.bastion_instance_type
//
//  kernel_id = "test"
//
//  key_name = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
//
////  monitoring {
////    enabled = true
////  }
//
//  network_interfaces {
//    associate_public_ip_address = true
//  }
//
//  vpc_security_group_ids = [aws_security_group.bastion.id]
//
//  tag_specifications {
//    resource_type = "instance"
//
//   tags = {
//      Name    = "${var.project}-bastion"
//      Project = var.project
//      Owner   = var.owner
//    }
//  }
//
//  user_data = "${base64encode(...)}"
//}
# LaunchConfigurations
## Bastion Host
resource "aws_launch_configuration" "bastion" {
  name_prefix                 = "bastion-"
  image_id                    = data.aws_ami.amazonlinux.id
  instance_type               = var.bastion_instance_type
  security_groups             = [aws_security_group.bastion.id]
  key_name                    = var.aws_key_pair_name == null ? aws_key_pair.ssh.0.key_name : var.aws_key_pair_name
  associate_public_ip_address = true
  ebs_optimized               = true
  enable_monitoring           = false
  iam_instance_profile        = aws_iam_instance_profile.bastion.id

  user_data = templatefile("${path.module}/userdata-bastion.tpl", {
    component = "bastion"
    domain    = var.hosted_zone
  })

  lifecycle {
    create_before_destroy = true
  }
}


resource "local_file" "debug" {
  filename = "${path.module}/userdata-debug.sh"
  content = templatefile("${path.module}/userdata-worker.tpl", {
    aws_region = var.aws_region,
    eni_ids    = aws_network_interface.enis.*.id
  })
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
  enable_monitoring           = false
  iam_instance_profile        = aws_iam_instance_profile.etcd-worker-master.id

  user_data = templatefile("${path.module}/userdata-etcd.tpl", {
    eni_ids = aws_network_interface.enis.*.id
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
  enable_monitoring           = false
  iam_instance_profile        = aws_iam_instance_profile.etcd-worker-master.id

  user_data = templatefile("${path.module}/userdata-master.tpl", {
    eni_ids = aws_network_interface.enis.*.id
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
  enable_monitoring           = false
  iam_instance_profile        = aws_iam_instance_profile.etcd-worker-master.id

  user_data = templatefile("${path.module}/userdata-worker.tpl", {
    aws_region = var.aws_region,
    eni_ids    = aws_network_interface.enis.*.id
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
  max_size                  = var.etcd_max_size
  min_size                  = var.etcd_min_size
  desired_capacity          = var.etcd_size
  force_delete              = true
  launch_configuration      = aws_launch_configuration.etcd.name
  vpc_zone_identifier       = aws_subnet.private.*.id
  health_check_grace_period = 180
  default_cooldown          = 180

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
  max_size                  = var.master_max_size
  min_size                  = var.master_min_size
  desired_capacity          = var.master_size
  force_delete              = true
  launch_configuration      = aws_launch_configuration.master.name
  vpc_zone_identifier       = aws_subnet.private.*.id
  load_balancers            = [aws_elb.master.id]
  health_check_grace_period = 180
  default_cooldown          = 180

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
  max_size                  = var.worker_max_size
  min_size                  = var.worker_min_size
  desired_capacity          = var.worker_size
  force_delete              = true
  launch_configuration      = aws_launch_configuration.worker.name
  vpc_zone_identifier       = aws_subnet.private.*.id
  health_check_grace_period = 180
  default_cooldown          = 180

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


# Route53 record for Bastion Host
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
