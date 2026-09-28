terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # กำหนด S3 / LocalStack backend สำหรับ Remote State
  backend "s3" {
    bucket                      = "taskflow-tfstate"
    key                         = "taskflow/lab08/terraform.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://host.docker.internal:4566"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    force_path_style            = true
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

#tfsec:ignore:aws-ec2-no-default-vpc: LocalStack EC2 Docker Manager uses its default VPC
#tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs: LocalStack does not emulate flow logs
resource "aws_default_vpc" "default" {
  #checkov:skip=CKV_AWS_148:LocalStack EC2 Docker Manager requires its default VPC
}

# Security Group อนุญาตเฉพาะ Port 8080 (แก้ปัญหา Open Security Group ตาม Audit)
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

resource "aws_instance" "taskflow_server" {
  #checkov:skip=CKV_AWS_88:LocalStack instance must be reachable by Jenkins for this lab
  #checkov:skip=CKV2_AWS_41:This LocalStack demo does not call AWS APIs from the instance
  #checkov:skip=CKV_AWS_126:LocalStack does not implement EC2 detailed monitoring (MonitorInstances)
  ami                         = "ami-7f4c2a91"
  instance_type               = "t3.nano"
  key_name                    = aws_key_pair.taskflow.key_name
  associate_public_ip_address = true
  monitoring                  = false
  ebs_optimized               = true
  vpc_security_group_ids      = [aws_default_security_group.taskflow_sg.id]

  metadata_options {
    http_tokens = "required" # ป้องกัน IMDSv1 ตามข้อเสนอแนะของ tfsec
  }

  root_block_device {
    volume_size = 15
    volume_type = "gp2"
    encrypted   = true # เปิด Encryption ให้ดิสก์ตาม security baseline
  }

  tags = {
    Name = "Taskflow-API-Host"
  }
}

output "instance_ip" {
  value       = aws_instance.taskflow_server.public_ip
  description = "The public IP address of the provisioned server"
}

output "instance_id" {
  value       = aws_instance.taskflow_server.id
  description = "The LocalStack EC2 Docker container identifier"
}

resource "aws_key_pair" "taskflow" {
  key_name   = "taskflow-lab08"
  public_key = var.ssh_public_key
}

variable "ssh_public_key" {
  type        = string
  description = "Public key for the temporary Lab 08 Ansible connection"
}
