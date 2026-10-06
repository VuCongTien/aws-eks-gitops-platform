resource "aws_db_subnet_group" "db_subnet_group" {
  name = "my-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet_db_1a.id,
    aws_subnet.private_subnet_db_1b.id
  ]
  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "postgres_db" {
  identifier        = "my-db"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  username = "postgres"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false

  skip_final_snapshot = true

  tags = {
    Name = "My Postgres Database"
  }
}
