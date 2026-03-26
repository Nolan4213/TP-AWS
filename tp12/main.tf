terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# ─── Data sources ───────────────────────────────────────────────
data "aws_caller_identity" "current" {}

data "aws_iam_role" "consumer" {
  name = var.consumer_role_name
}

# ─── KMS Key ────────────────────────────────────────────────────
resource "aws_kms_key" "tp12" {
  description             = "Clé KMS dédiée TP12 — chiffrement S3 et Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowConsumerDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_iam_role.consumer.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSecretsManagerUse"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowS3Use"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Project = "TP12"
    Env     = "training"
  }
}

resource "aws_kms_alias" "tp12" {
  name          = "alias/tp12-key"
  target_key_id = aws_kms_key.tp12.key_id
}
# ─── S3 — bucket dédié TP12 ─────────────────────────────────────
resource "aws_s3_bucket" "tp12" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Project = "TP12"
    Env     = "training"
  }
}

resource "aws_s3_bucket_public_access_block" "tp12" {
  bucket = aws_s3_bucket.tp12.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tp12" {
  bucket = aws_s3_bucket.tp12.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ─── S3 — chiffrement KMS sur bucket TP6 ────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "tp6_kms" {
    bucket     = aws_s3_bucket.tp12.id
  depends_on = [aws_s3_bucket.tp12]


  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tp12.arn
    }
    bucket_key_enabled = true
  }
}

# ─── Secrets Manager ────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "tp12/db-credentials"
  description             = "Credentials DB simulés pour TP12 — consommés au runtime par Lambda"
  kms_key_id              = aws_kms_key.tp12.arn
  recovery_window_in_days = 0

  tags = {
    Project = "TP12"
    Env     = "training"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.secret_username
    password = var.secret_password
    engine   = "postgres"
    host     = "tp7-rds.eu-west-3.rds.amazonaws.com"
    port     = 5432
    dbname   = "tpdb"
  })
}

# ─── IAM — mise à jour rôle consumer ────────────────────────────
resource "aws_iam_policy" "consumer_secrets_kms" {
  name        = "tp12-consumer-secrets-kms-policy"
  description = "Accès minimal Secret Manager + KMS pour tp10-consumer"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGetSecret"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.tp12.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "consumer_secrets_kms" {
  role       = var.consumer_role_name
  policy_arn = aws_iam_policy.consumer_secrets_kms.arn
}

# ─── Lambda consumer — mise à jour env var ──────────────────────



# ─── GuardDuty ──────────────────────────────────────────────────
resource "aws_guardduty_detector" "tp12" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false
        }
      }
    }
  }

  tags = {
    Project = "TP12"
    Env     = "training"
  }
}
