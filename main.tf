terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }

    # cloudflare = {
    #   source  = "cloudflare/cloudflare"
    #   version = "~> 4.0"
    # }
  }

  required_version = ">= 1.9.8"
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      environment = "production"
      project = "langomine"
      manager = "terraform"
    }
  }
}

# provider "cloudflare" {
#   api_token = var.cloudflare_api_token
# }

resource "aws_resourcegroups_group" "this" {
  name = "langomine-rg"

  resource_query {
    query = <<JSON
    {
        "ResourceTypeFilters": [
            "AWS::AllSupported"
        ],
        "TagFilters": [
            {
            "Key": "project",
            "Values": ["langomine"]
            },
            {
            "Key": "manager",
            "Values": ["terraform"]
            }
        ]
    }
    JSON
  }
}

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "this" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1"
}

resource "aws_network_interface" "this" {
  subnet_id   = aws_subnet.this.id
  private_ips = ["10.0.10.100"]
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKe3P2g9JU3DkBQ7b9UmuED0aYp828USxD2CQylv6qjB aws.deployer.langomine.com"
}

data "http" "cloudflare_ips" {
  url = "https://api.cloudflare.com/client/v4/ips"
  request_headers = {
    Accept = "application/json"
  }
}

locals {
  cf_ips = jsondecode(data.http.cloudflare_ips.body)
}

resource "aws_security_group" "this" {
  name        = "langomine_sg"
  description = "Define rules for Langomine server"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = toset(local.cf_ips.result.ipv4_cidrs)
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv6" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv6         = toset(local.cf_ips.result.ipv6_cidrs)
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_instance" "this" {
  ami           = aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.this.id
    device_index         = 0
  }
}
