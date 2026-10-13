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

  source_security_group_id = aws_security_group.eks_sg.id

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
