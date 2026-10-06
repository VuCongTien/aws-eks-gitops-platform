#clear
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-custom-vpc"
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
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

#clear
resource "aws_route_table" "public-rtb-lab-eks" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public-rtb-lab-eks"
  }
}

#clear
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public-rtb-lab-eks.id
}

#clear
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_1b.id
  route_table_id = aws_route_table.public-rtb-lab-eks.id
}


#clear
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main_igw]

  tags = {
    Name = "nat-eip"
  }
}

#clear
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet_1a.id

  tags = {
    Name = "main-nat-gateway"
  }

  depends_on = [aws_internet_gateway.main_igw]
}

#clear
resource "aws_route_table" "private_eks_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "private-eks-rt"
  }
}

#clear
resource "aws_route_table_association" "private_assoc_eks_1a" {
  subnet_id      = aws_subnet.private_subnet_eks_1a.id
  route_table_id = aws_route_table.private_eks_rt.id
}

#clear
resource "aws_route_table_association" "private_assoc_eks_1b" {
  subnet_id      = aws_subnet.private_subnet_eks_1b.id
  route_table_id = aws_route_table.private_eks_rt.id
}

#clear
resource "aws_route_table" "private_db_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "private-db-rt"
  }
}

#clear
resource "aws_route_table_association" "private_assoc_db_1a" {
  subnet_id      = aws_subnet.private_subnet_db_1a.id
  route_table_id = aws_route_table.private_db_rt.id
}

#clear
resource "aws_route_table_association" "private_assoc_db_1b" {
  subnet_id      = aws_subnet.private_subnet_db_1b.id
  route_table_id = aws_route_table.private_db_rt.id
}


