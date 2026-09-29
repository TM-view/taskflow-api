terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6.1"
    }
  }
  # Keep Terraform state in LocalStack S3, with object versioning and S3 locking.
  backend "s3" {
    bucket         = "taskflow-tfstate"
    key            = "lab/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    use_path_style = true

    endpoints = {
      s3 = "http://host.docker.internal:4566"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2 = "http://host.docker.internal:4566"
    s3  = "http://host.docker.internal:4566"
  }
}

# Freemium LocalStack supports EC2 API records but not Docker-backed EC2 hosts.
# Terraform therefore creates the SSH-capable lab host through the mounted Docker engine.
provider "docker" {
  host = "unix:///var/run/docker.sock"
}

#tfsec:ignore:aws-ec2-no-default-vpc: LocalStack EC2 Docker Manager uses its default VPC
#tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs: LocalStack does not emulate flow logs
resource "aws_default_vpc" "default" {
  #checkov:skip=CKV_AWS_148:LocalStack EC2 Docker Manager requires its default VPC
}

# LocalStack's mock EC2 records this lab security group. Docker port publishing
# below provides SSH and a dynamically assigned host port for container port 8080.
resource "aws_default_security_group" "taskflow_sg" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    description = "SSH from the lab network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Allow port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # หลีกเลี่ยง 0.0.0.0/0 เพื่อให้ผ่าน Checkov/tfsec
  }

  egress {
    description = "Allow outbound traffic only within the LocalStack lab VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "docker_image" "taskflow_host" {
  name         = "taskflow-lab08-host:latest"
  keep_locally = false

  build {
    context    = "${path.module}/../ansible"
    dockerfile = "Dockerfile.host"
    build_args = {
      SSH_PUBLIC_KEY = var.ssh_public_key
    }
  }

  triggers = {
    dockerfile  = filesha256("${path.module}/../ansible/Dockerfile.host")
    ssh_key_sha = sha256(var.ssh_public_key)
  }
}

resource "docker_container" "taskflow_host" {
  name  = "taskflow-lab08-host"
  image = docker_image.taskflow_host.image_id

  ports {
    internal = 22
  }

  ports {
    internal = 8080
  }

  # The host runs Docker CLI commands against the same engine Jenkins uses.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

}

output "instance_ip" {
  value       = "host.docker.internal"
  description = "The Docker host address used to reach the Terraform-managed Lab 08 host"
}


output "ansible_host" {
  value       = "host.docker.internal"
  description = "Host name reachable from Jenkins containers"
}

output "ansible_port" {
  value       = one([for port in docker_container.taskflow_host.ports : port.external if port.internal == 22])
  description = "Dynamically published SSH port for the Ansible host"
}

output "application_port" {
  value       = one([for port in docker_container.taskflow_host.ports : port.external if port.internal == 8080])
  description = "Dynamically published host port for container port 8080"
}


variable "ssh_public_key" {
  type        = string
  description = "Public key for the temporary Lab 08 Ansible connection"
}
