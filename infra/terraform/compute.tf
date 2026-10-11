
variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "app" {
  name        = "nodejs-api-sg"
  description = "Node.js API host; no direct SSH access"
  vpc_id      = aws_vpc.main.id

  # Temporary direct HTTP access for initial verification.
  # We'll replace this with ALB-only access for blue-green deployment.

  ingress {
    description = "HTTP web traffic and certificate validation"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS for secure API traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound access for updates, SSM, and image pulls"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "nodejs-api-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 12
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf update -y
    dnf install -y docker nginx certbot python3-certbot-nginx git

    systemctl enable --now docker
    usermod -aG docker ec2-user

    mkdir -p /opt/nodejs-api
    mkdir -p /var/www/certbot
    mkdir -p /etc/nginx/upstreams

    if [ ! -d /opt/nodejs-api/repo/.git ]; then
      git clone https://github.com/sandeep9526/nodejs-devops-setup.git /opt/nodejs-api/repo
    fi

    # Install Nginx configuration and initial blue upstream.
    install -m 0644 /opt/nodejs-api/repo/infra/nginx/nodejs-api.conf /etc/nginx/conf.d/nodejs-api.conf

    cat > /etc/nginx/upstreams/nodejs-api-upstream.conf <<'UPSTREAM'
    upstream nodejs_api {
        server 127.0.0.1:3001;
        keepalive 16;
    }
    UPSTREAM

    nginx -t
    systemctl enable --now nginx

    chown -R ec2-user:ec2-user /opt/nodejs-api
  EOF

  tags = {
    Name             = "nodejs-api-production"
    DeploymentTarget = "nodejs-api-production"
    ManagedBy        = "Terraform"
    Environment      = "production"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ec2_ssm_core
  ]
}

output "ec2_instance_id" {
  description = "Production EC2 instance ID for SSM deployments"
  value       = aws_instance.app.id
}

output "ec2_public_ip" {
  description = "Public IP for initial HTTP verification"
  value       = aws_instance.app.public_ip
}