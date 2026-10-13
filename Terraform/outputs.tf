
output "vpc" {
  description = "Main VPC information"

  value = {
    id         = aws_vpc.main.id
    cidr_block = aws_vpc.main.cidr_block
    name       = aws_vpc.main.tags.Name
  }
}

output "public_subnets" {
  description = "Public subnet information"

  value = {
    subnet_1a = {
      id                = aws_subnet.public_subnet_1a.id
      cidr_block        = aws_subnet.public_subnet_1a.cidr_block
      availability_zone = aws_subnet.public_subnet_1a.availability_zone
    }
    subnet_1b = {
      id                = aws_subnet.public_subnet_1b.id
      cidr_block        = aws_subnet.public_subnet_1b.cidr_block
      availability_zone = aws_subnet.public_subnet_1b.availability_zone
    }
  }
}

output "private_eks_subnets" {
  description = "Private subnet information for EKS"

  value = {
    subnet_1a = {
      id                = aws_subnet.private_subnet_eks_1a.id
      cidr_block        = aws_subnet.private_subnet_eks_1a.cidr_block
      availability_zone = aws_subnet.private_subnet_eks_1a.availability_zone
    }
    subnet_1b = {
      id                = aws_subnet.private_subnet_eks_1b.id
      cidr_block        = aws_subnet.private_subnet_eks_1b.cidr_block
      availability_zone = aws_subnet.private_subnet_eks_1b.availability_zone
    }
  }
}

output "private_db_subnets" {
  description = "Private subnet information for the database"

  value = {
    subnet_1a = {
      id                = aws_subnet.private_subnet_db_1a.id
      cidr_block        = aws_subnet.private_subnet_db_1a.cidr_block
      availability_zone = aws_subnet.private_subnet_db_1a.availability_zone
    }
    subnet_1b = {
      id                = aws_subnet.private_subnet_db_1b.id
      cidr_block        = aws_subnet.private_subnet_db_1b.cidr_block
      availability_zone = aws_subnet.private_subnet_db_1b.availability_zone
    }
  }
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main_igw.id
}

output "nat_gateway" {
  description = "NAT Gateway and Elastic IP information"

  value = {
    id        = aws_nat_gateway.main.id
    public_ip = aws_eip.nat.public_ip
    subnet_id = aws_nat_gateway.main.subnet_id
  }
}

output "route_tables" {
  description = "Route table IDs and subnet associations"

  value = {
    public = {
      id = aws_route_table.public-rtb-lab-eks.id
      subnet_ids = [
        aws_subnet.public_subnet_1a.id,
        aws_subnet.public_subnet_1b.id,
      ]
      default_route = "Internet Gateway"
    }
    private_eks = {
      id = aws_route_table.private_eks_rt.id
      subnet_ids = [
        aws_subnet.private_subnet_eks_1a.id,
        aws_subnet.private_subnet_eks_1b.id,
      ]
      default_route = "NAT Gateway"
    }
    private_db = {
      id = aws_route_table.private_db_rt.id
      subnet_ids = [
        aws_subnet.private_subnet_db_1a.id,
        aws_subnet.private_subnet_db_1b.id,
      ]
      default_route = "NAT Gateway"
    }
  }
}

output "database_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = aws_db_instance.postgres_db.address
}

output "database_port" {
  description = "PostgreSQL RDS port"
  value       = aws_db_instance.postgres_db.port
}

output "database_secret_arn" {
  description = "ARN of the PostgreSQL credentials secret"
  value       = aws_secretsmanager_secret.db_secret.arn
}

output "ecr_repositories" {
  description = "ECR repository information for backend and frontend images"

  value = {
    backend = {
      name = aws_ecr_repository.backend.name
      url  = aws_ecr_repository.backend.repository_url
      arn  = aws_ecr_repository.backend.arn
    }
    frontend = {
      name = aws_ecr_repository.frontend.name
      url  = aws_ecr_repository.frontend.repository_url
      arn  = aws_ecr_repository.frontend.arn
    }
  }
}