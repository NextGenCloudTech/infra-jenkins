# Define variables
variable "ami_id" {
  description = "The ID of the AMI to use for the EC2 instance"
}

variable "eip_allocation_id" {
  description = "The allocation ID of the Elastic IP to associate with the EC2 instance"
}

variable "alerts_email" {
  description = "The email address for Let's Encrypt SSL certificate renewal alerts"
}

# Provider block
provider "aws" {
  region = "us-east-1" # Replace with your desired region
}

# VPC
resource "aws_vpc" "jenkins_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Subnet
resource "aws_subnet" "jenkins_subnet" {
  vpc_id     = aws_vpc.jenkins_vpc.id
  cidr_block = "10.0.1.0/24"
}

# Internet Gateway
resource "aws_internet_gateway" "jenkins_igw" {
  vpc_id = aws_vpc.jenkins_vpc.id
}

# Route Table
resource "aws_route_table" "jenkins_rt" {
  vpc_id = aws_vpc.jenkins_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.jenkins_igw.id
  }
}

# Route Table Association
resource "aws_route_table_association" "jenkins_rta" {
  subnet_id      = aws_subnet.jenkins_subnet.id
  route_table_id = aws_route_table.jenkins_rt.id
}

# Security Group
resource "aws_security_group" "jenkins_sg" {
  vpc_id = aws_vpc.jenkins_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "jenkins_instance" {
  ami             = var.ami_id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.jenkins_subnet.id
  security_groups = [aws_security_group.jenkins_sg.id]

  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
   
    # Start Nginx and Jenkins
    sudo systemctl start nginx
    sudo systemctl start jenkins

    # Configure Nginx for Jenkins
    cat <<EOT > /etc/nginx/conf.d/jenkins.conf
    # Jenkins Nginx Proxy configuration
    #################################################
    upstream jenkins {
      server 127.0.0.1:8080 fail_timeout=0;
    }

    server {
      listen 80;
      server_name jenkins.nextgencloudtech.online;

      location / {
        proxy_set_header        Host \$host:\$server_port;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_pass              http://jenkins;
        # Required for new HTTP-based CLI
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off; # Required for HTTP-based CLI to work over SSL
      }
    }    
    EOT

    sudo nginx -t
    sudo systemctl enable --now nginx
    sudo systemctl restart nginx

    export DOMAIN="jenkins.nextgencloudtech.online"
    export ALERTS_EMAIL="${var.alerts_email}"

    # Obtain Let's Encrypt SSL certificate
    sudo certbot --nginx --redirect -d $DOMAIN --preferred-challenges http --agree-tos -n -m $ALERTS_EMAIL --keep-until-expiring
  EOF
}

# Use the existing Elastic IP
resource "aws_eip_association" "jenkins_eip_assoc" {
  instance_id   = aws_instance.jenkins_instance.id
  allocation_id = var.eip_allocation_id
}

# Output the instance public IP
output "jenkins_instance_public_ip" {
  value = aws_instance.jenkins_instance.public_ip
}
