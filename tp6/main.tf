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


resource "aws_s3_bucket" "tp6" {
  bucket = var.bucket_name

  tags = {
    Name       = var.bucket_name
    Project    = "AWS-TP"
    Owner      = "ops-student"
    Env        = "dev"
    CostCenter = "TP-Cloud"
  }
}

# ─── 2. Blocage accès public ──────────────────────────────────────────────
# Empêche TOUTE exposition publique du bucket et de ses objets.
# block_public_policy = false est nécessaire pour pouvoir appliquer
# notre bucket policy TLS ci-dessous (sinon Terraform ne peut pas la poser).
resource "aws_s3_bucket_public_access_block" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  block_public_acls       = true   # Bloque les ACL publiques
  ignore_public_acls      = true   # Ignore les ACL publiques existantes
  block_public_policy     = false  # Laisse passer notre policy TLS
  restrict_public_buckets = true   # Interdit l'accès public même avec policy
}

# ─── 3. Versioning ────────────────────────────────────────────────────────
# Chaque modification d'un objet crée une nouvelle version.
# On peut restaurer n'importe quelle version précédente.
resource "aws_s3_bucket_versioning" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ─── 4. Chiffrement SSE-S3 par défaut ────────────────────────────────────
# Tous les objets uploadés sont automatiquement chiffrés avec AES-256.
# Même si quelqu'un accède au stockage physique, les données sont illisibles.
resource "aws_s3_bucket_server_side_encryption_configuration" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true  # Réduit les coûts de chiffrement
  }
}

# ─── 5. Bucket Policy TLS obligatoire ────────────────────────────────────
# Refuse TOUTES les requêtes qui n'utilisent pas HTTPS (TLS).
# aws:SecureTransport = false → la requête arrive en HTTP → on la bloque.
# Sans cette policy, quelqu'un pourrait intercepter les données en transit.
resource "aws_s3_bucket_policy" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # On attend que le blocage public soit en place avant d'appliquer la policy
  depends_on = [aws_s3_bucket_public_access_block.tp6]
}

# ─── 6. Lifecycle ─────────────────────────────────────────────────────────
# Déplace automatiquement les objets vers des classes de stockage moins chères
# au fil du temps, puis les supprime. Réduit les coûts sans intervention manuelle.
#
# STANDARD     → par défaut, accès fréquent
# STANDARD_IA  → accès peu fréquent, moins cher (-40%)
# GLACIER      → archivage, très peu cher mais récupération lente
resource "aws_s3_bucket_lifecycle_configuration" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  rule {
    id     = "tp6-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""  # S'applique à tous les objets du bucket
    }

    # Jour 30 : transition vers STANDARD_IA
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Jour 90 : transition vers GLACIER (archivage)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Jour 365 : suppression définitive
    expiration {
      days = 365
    }

    # Les anciennes versions sont supprimées après 30 jours
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # Le versioning doit être actif avant de configurer le lifecycle
  depends_on = [aws_s3_bucket_versioning.tp6]
}

# ─── 7. Objet de test - Version 1 ─────────────────────────────────────────
# Terraform upload directement un fichier texte comme premier objet.
# Cela crée automatiquement la Version 1 dans le bucket versionné.
resource "aws_s3_object" "test" {
  bucket  = aws_s3_bucket.tp6.id
  key     = "test.txt"
  content = "Version 1 - contenu initial - TP6"

  depends_on = [aws_s3_bucket_versioning.tp6]
}
