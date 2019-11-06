data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }
}


data "aws_availability_zones" "available" {
  state = "available"
}

# Get local workstation's external IPv4 address
data "http" "workstation-external-ip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  workstation-external-cidr = "${chomp(data.http.workstation-external-ip.body)}/32"
}

# Get HostedZone ID
data "aws_route53_zone" "selected" {
  name         = "${var.hosted_zone}."
  private_zone = false
}

# AWS VPC
resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
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
  count                   = var.availability_zones
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project}-private-${count.index}"
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


resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "${var.project}-rt"
    Project = var.project
    Owner   = var.owner
  }
}


resource "aws_route_table_association" "rtassoc" {
  count          = var.availability_zones
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.rt.id
}


resource "aws_key_pair" "ssh" {
  key_name   = "${var.owner}-key"
  public_key = file(var.ssh_public_key_path)
}

# SecurityGroups
resource "aws_security_group" "allow_workstation" {
  name        = "allow_workstationctl_ssh_http_https"
  description = "Allow kubectl ssh http https inbound traffic for kubectl"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.workstation-external-cidr]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.workstation-external-cidr]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.workstation-external-cidr]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [local.workstation-external-cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-workstation"
    Project = var.project
    Owner   = var.owner
  }
}


resource "aws_security_group" "allow_internal" {
  name        = "allow_all_internal_vpc"
  description = "Allow all internal VPC communication"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name    = "${var.project}-sg-internal"
    Project = var.project
    Owner   = var.owner
  }
}

# etcd EC2 Instances
resource "aws_instance" "etcd" {
  count         = var.etcd_instances
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.etcd_instance_type
  subnet_id     = aws_subnet.public[count.index].id
  key_name      = aws_key_pair.ssh.key_name
  user_data = templatefile("${path.module}/userdata.tpl", {
    component = "etcd"
    domain    = var.hosted_zone
  })
  ebs_optimized          = true
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.allow_workstation.id, aws_security_group.allow_internal.id]


  tags = {
    Name    = "${var.project}-master-${count.index + 1}"
    Project = var.project
    Owner   = var.owner
  }
}

# Kubernetes Master EC2 Instances
resource "aws_instance" "master" {
  count         = var.master_instances
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.master_instance_type
  subnet_id     = aws_subnet.public[count.index].id
  key_name      = aws_key_pair.ssh.key_name
  user_data = templatefile("${path.module}/userdata.tpl", {
    component = "master"
    domain    = var.hosted_zone
  })
  ebs_optimized          = true
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.allow_workstation.id, aws_security_group.allow_internal.id]


  tags = {
    Name    = "${var.project}-master-${count.index + 1}"
    Project = var.project
    Owner   = var.owner
  }
}

# Kubernetes Worker EC2 Instances
resource "aws_instance" "worker" {
  count         = var.worker_instances
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  subnet_id     = aws_subnet.public[count.index].id
  key_name      = aws_key_pair.ssh.key_name
  user_data = templatefile("${path.module}/userdata.tpl", {
    component = "worker"
    domain    = var.hosted_zone
  })
  ebs_optimized          = true
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.allow_workstation.id, aws_security_group.allow_internal.id]

  tags = {
    Name    = "${var.project}-worker-${count.index + 1}"
    Project = var.project
    Owner   = var.owner
  }
}


# etcd Route53 records
resource "aws_route53_record" "etcd-public" {
  count   = var.availability_zones
  zone_id = data.aws_route53_zone.selected.id
  name    = "etcd${count.index + 1}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.etcd[count.index].public_ip]
}

resource "aws_route53_record" "etcd-private" {
  count   = var.availability_zones
  zone_id = data.aws_route53_zone.selected.id
  name    = "etcd${count.index + 1}.internal"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.etcd[count.index].private_ip]
}


# Kubernetes Master Route53 records
resource "aws_route53_record" "master-public" {
  count   = var.availability_zones
  zone_id = data.aws_route53_zone.selected.id
  name    = "master${count.index + 1}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.master[count.index].public_ip]
}

resource "aws_route53_record" "master-private" {
  count   = var.availability_zones
  zone_id = data.aws_route53_zone.selected.id
  name    = "master${count.index + 1}.internal"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.master[count.index].private_ip]
}


# Kubernetes Worker Route53 records
resource "aws_route53_record" "worker-public" {
  count   = var.availability_zones
  zone_id = data.aws_route53_zone.selected.id
  name    = "worker${count.index + 1}"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.worker[count.index].public_ip]
}

resource "aws_route53_record" "worker-private" {
  count   = var.availability_zones
  zone_id = data.aws_route53_zone.selected.id
  name    = "worker${count.index + 1}.internal"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.worker[count.index].private_ip]
}

