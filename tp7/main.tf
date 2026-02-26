terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  profile = var.profile
  region  = var.region
}

# ─── DB Subnet Group ───────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "tp7" {
  name       = "tp7-db-subnet-group"
  subnet_ids = [var.subnet_priv_a, var.subnet_priv_b]

  tags = {
    Name = "tp7-db-subnet-group"
  }
}

# ─── Security Group RDS ────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "tp7-sg-rds"
  description = "Autorise uniquement le SG app sur port PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL depuis SG app uniquement"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.sg_app_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tp7-sg-rds"
  }
}

# ─── Instance RDS PostgreSQL ───────────────────────────────────────────────────
resource "aws_db_instance" "tp7" {
  identifier             = "tp7-postgres"
  engine                 = "postgres"
  engine_version         = "16.6"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  storage_encrypted      = true

  db_name                = "tp7db"
  username               = var.db_username
  password               = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.tp7.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  maintenance_window      = "mon:03:00-mon:04:00"

  skip_final_snapshot    = true

  tags = {
    Name = "tp7-postgres"
  }
}
