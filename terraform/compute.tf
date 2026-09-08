data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  app_user_data = <<-EOF
    #!/bin/bash
    set -e

    apt-get update
    apt-get install -y docker.io awscli

    systemctl enable docker
    systemctl start docker

    usermod -aG docker ubuntu

    # Ensure AWS Systems Manager Agent is available
    if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
      snap install amazon-ssm-agent --classic
    fi

    snap start amazon-ssm-agent || true
  EOF
}

resource "aws_instance" "blue" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.app.id]

  iam_instance_profile = aws_iam_instance_profile.app_ec2.name

  user_data = local.app_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.project_name}-blue"
    Environment = "BLUE"
  }
}

resource "aws_instance" "green" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_b.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.app.id]

  iam_instance_profile = aws_iam_instance_profile.app_ec2.name

  user_data = local.app_user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.project_name}-green"
    Environment = "GREEN"
  }
}
