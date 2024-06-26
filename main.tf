# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# 1. Create vpc
resource "aws_vpc" "tf-vpc" {
  cidr_block       = "10.0.0.0/16"
  tags = {
    Name = "tf-vpc"
  }
}
# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.tf-vpc.id

  tags = {
    Name = "tf-igw"
  }
}
# 3. Create Custom Route Table
resource "aws_route_table" "tf-route-table" {
  vpc_id = aws_vpc.tf-vpc.id

  route {
    cidr_block = aws_vpc.tf-vpc.cidr_block
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "tf-route"
  }
}
# Create Route table Private
resource "aws_route_table" "tf-prvroute-table" {
  vpc_id = aws_vpc.tf-vpc.id

  route {
    cidr_block = aws_vpc.tf-vpc.cidr_block
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.tf-nat-2.id
  }

  tags = {
    Name = "tf-prvroute"
  }
}
# Create NAT
resource "aws_nat_gateway" "tf-nat-2" {
  subnet_id     = aws_subnet.tf-subnet-2.id
  allocation_id = aws_eip.tf-nat-eip.id
  tags = {
    Name = "gw-NAT-2"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}
# 4. Create a Subnet
resource "aws_subnet" "tf-subnet-1" {
  vpc_id     = aws_vpc.tf-vpc.id
  cidr_block = "10.0.0.0/22"
  availability_zone = "us-east-1a"

  tags = {
    Name = "tf-subnet-1"
  }
}
resource "aws_subnet" "tf-subnet-2" {
  vpc_id     = aws_vpc.tf-vpc.id
  cidr_block = "10.0.4.0/22"
  availability_zone = "us-east-1b"

  tags = {
    Name = "tf-subnet-2"
  }
}
resource "aws_subnet" "tf-prvsubnet-1" {
  vpc_id     = aws_vpc.tf-vpc.id
  cidr_block = "10.0.8.0/22"
  availability_zone = "us-east-1a"

  tags = {
    Name = "tf-prvsubnet-1"
  }
}
resource "aws_subnet" "tf-prvsubnet-2" {
  vpc_id     = aws_vpc.tf-vpc.id
  cidr_block = "10.0.12.0/22"
  availability_zone = "us-east-1b"

  tags = {
    Name = "tf-prvsubnet-2"
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "sub1" {
  subnet_id      = aws_subnet.tf-subnet-1.id
  route_table_id = aws_route_table.tf-route-table.id
}
resource "aws_route_table_association" "sub2" {
  subnet_id      = aws_subnet.tf-subnet-2.id
  route_table_id = aws_route_table.tf-route-table.id
}
# Associate with private route table
resource "aws_route_table_association" "prv-sub1" {
  subnet_id      = aws_subnet.tf-prvsubnet-1.id
  route_table_id = aws_route_table.tf-prvroute-table.id
}
resource "aws_route_table_association" "prv-sub2" {
  subnet_id      = aws_subnet.tf-prvsubnet-2.id
  route_table_id = aws_route_table.tf-prvroute-table.id
}
# 6. Create Security Group to allow port 22,80,443
resource "aws_security_group" "tf-security_group" {
  name        = "allow_web"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.tf-vpc.id

  ingress {
    cidr_blocks       = ["0.0.0.0/0"]
    from_port         = 443
    protocol          = "tcp"
    to_port           = 443
  }

  ingress {
    cidr_blocks       = ["0.0.0.0/0"]
    from_port         = 22
    protocol          = "tcp"
    to_port           = 22
  }

  ingress {
    cidr_blocks       = ["0.0.0.0/0"]
    from_port         = 80
    protocol          = "tcp"
    to_port           = 80
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "tf-sg"
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "tf-network" {
  subnet_id       = aws_subnet.tf-subnet-1.id
  security_groups = [aws_security_group.tf-security_group.id]
  private_ip = "10.0.0.50"
}
# 8. Assign an elastic IP to the network interface created in step 7
#EIP for ENI
resource "aws_eip" "tf-eip" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.tf-network.id

  depends_on = [ aws_network_interface.tf-network ]
}
#EIP for NAT
resource "aws_eip" "tf-nat-eip" {
  domain                    = "vpc"
}
# 9. Create Ubuntu server and install/enable apache2
resource "aws_key_pair" "kp" {
  public_key = file("./ec2key.pub")
  key_name = "ec2kp"
}

resource "aws_instance" "tf-instance" {
  ami           = "ami-0e001c9271cf7f3b9"
  instance_type = "t2.micro"
  # subnet_id = aws_subnet.tf-subnet-1.id
  # security_groups = [aws_security_group.tf-security_group.id]
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.tf-network.id
  }
  key_name = aws_key_pair.kp.key_name
  tags = {
    Name = "ec2"
  }
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install nginx -y
    sudo systemctl start nginx
    EOF

  depends_on = [ aws_eip.tf-eip ]
}

output "public_ip" {
  value = aws_instance.tf-instance.public_ip
} 

resource "aws_instance" "tf-prv-instance1" {
  ami           = "ami-0e001c9271cf7f3b9"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.tf-prvsubnet-1.id
  vpc_security_group_ids = [aws_security_group.tf-security_group.id]
  
  key_name = aws_key_pair.kp.key_name
  tags = {
    Name = "prv-ec2-1"
  }
}
resource "aws_instance" "tf-prv-instance2" {
  ami           = "ami-0e001c9271cf7f3b9"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.tf-prvsubnet-2.id
  vpc_security_group_ids = [aws_security_group.tf-security_group.id]
  
  key_name = aws_key_pair.kp.key_name
  tags = {
    Name = "prv-ec2-2"
  }
}

output "prv_ip_1" {
  value = aws_instance.tf-prv-instance1.private_ip
} 

output "prv_ip_2" {
  value = aws_instance.tf-prv-instance2.private_ip
} 