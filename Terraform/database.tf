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

ephemeral "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_secret" {
  name = "my-postgres-credentials-v2"
}

resource "aws_secretsmanager_secret_version" "db_secret" {
  secret_id = aws_secretsmanager_secret.db_secret.id

  secret_string_wo = jsonencode({
    username = "dbadmin"
    password = ephemeral.random_password.db_password.result
  })

  secret_string_wo_version = 1
}

ephemeral "aws_secretsmanager_secret_version" "db_secret" {
  secret_id = aws_secretsmanager_secret_version.db_secret.secret_id
}

resource "aws_db_instance" "postgres_db" {
  identifier        = "my-db"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  multi_az = false

  username = "dbadmin"

  password_wo = jsondecode(
    ephemeral.aws_secretsmanager_secret_version.db_secret.secret_string
  )["password"]

  password_wo_version = aws_secretsmanager_secret_version.db_secret.secret_string_wo_version

  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  publicly_accessible = false
  storage_encrypted   = true

  skip_final_snapshot = true
}