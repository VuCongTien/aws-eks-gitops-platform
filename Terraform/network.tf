#clear
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-custom-vpc"
  }
}

# clear
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

#clear
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_1a
  availability_zone       = var.availability_zone_1a
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-1a"
  }
}

#clear
resource "aws_subnet" "public_subnet_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_1b
  availability_zone       = var.availability_zone_1b
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-1b"
  }
}

#clear
resource "aws_subnet" "private_subnet_eks_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_eks_1a
  availability_zone = var.availability_zone_1a

  tags = {
    Name = "private-subnet-eks-1a"
  }
}

#clear
resource "aws_subnet" "private_subnet_eks_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_eks_1b
  availability_zone = var.availability_zone_1b

  tags = {
    Name = "private-subnet-eks-1b"
  }
}

#clear
resource "aws_subnet" "private_subnet_db_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_db_1a
  availability_zone = var.availability_zone_1a

  tags = {
    Name = "private-subnet-db-1a"
  }
}

#clear
resource "aws_subnet" "private_subnet_db_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr_db_1b
  availability_zone = var.availability_zone_1b

  tags = {
    Name = "private-subnet-db-1b"
  }
}

#clear
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}




