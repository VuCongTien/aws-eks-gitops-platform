resource "aws_security_group" "public_sg" {
  name        = "public-sg"
  description = "Security Group for public subnet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "public-sg"
  }
}

resource "aws_security_group" "eks_sg" {
  name        = "eks-sg"
  description = "Security Group for EKS nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "eks-sg"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Security Group for PostgreSQL RDS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "db-sg"
  }
}


resource "aws_security_group_rule" "allow_eks_to_rds" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.db_sg.id

  source_security_group_id = data.aws_eks_cluster.current.vpc_config[0].cluster_security_group_id

  description = "Allow PostgreSQL from EKS nodes"
}

resource "aws_security_group_rule" "eks_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic from EKS"
}

resource "aws_security_group_rule" "public_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.public_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}

resource "aws_security_group_rule" "alb_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.public_sg.id
  cidr_blocks       = ["0.0.0.0/0"]

  description = "Allow HTTP from Internet"
}

resource "aws_security_group_rule" "alb_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.public_sg.id
  cidr_blocks       = ["0.0.0.0/0"]

  description = "Allow HTTPS from Internet"
}

resource "aws_security_group_rule" "allow_alb_to_eks" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_sg.id
  source_security_group_id = aws_security_group.public_sg.id

  description = "Allow traffic from ALB to EKS"
}

resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "vpc-endpoint-sg"
  description = "Allow EKS nodes to access interface VPC endpoints over HTTPS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "vpc-endpoint-sg"
  }
}

data "aws_eks_cluster" "current" {
  name       = aws_eks_cluster.main.name
  depends_on = [aws_eks_cluster.main]
}

resource "aws_security_group_rule" "vpc_endpoint_https_from_eks" {
  type      = "ingress"
  from_port = 443
  to_port   = 443
  protocol  = "tcp"

  security_group_id = aws_security_group.vpc_endpoint_sg.id

  source_security_group_id = data.aws_eks_cluster.current.vpc_config[0].cluster_security_group_id

  description = "Allow HTTPS from EKS worker nodes to VPC endpoints"
}