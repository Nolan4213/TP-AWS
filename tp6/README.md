# TP6 — S3 Sécurité : versioning, chiffrement, TLS, lifecycle

> **Objectif** : Construire un bucket S3 conforme aux bonnes pratiques de sécurité :
> blocage public, versioning, chiffrement AES-256, politique TLS obligatoire et règle lifecycle.

---

## Architecture de sécurité

```
Client
  │
  │ HTTPS uniquement (TLS forcé par bucket policy)
  ▼
┌─────────────────────────────────────────────┐
│  Bucket S3 : tp6-ops-student-792390865255   │
│                                             │
│  Blocage public    : actif                  │
│  Chiffrement       : AES-256 (SSE-S3)       │
│  Versioning        : actif                  │
│  Transport TLS     : obligatoire            │
│  Lifecycle         : J30 → J90 → J365       │
└─────────────────────────────────────────────┘
```

---

## Ressources Terraform

| Ressource | Description |
|---|---|
| `aws_s3_bucket` | Bucket dédié au projet |
| `aws_s3_bucket_public_access_block` | Blocage total des accès publics |
| `aws_s3_bucket_versioning` | Versioning activé |
| `aws_s3_bucket_server_side_encryption_configuration` | Chiffrement AES-256 par défaut |
| `aws_s3_bucket_policy` | Refus de tout accès non TLS |
| `aws_s3_bucket_lifecycle_configuration` | Transition et expiration automatiques |
| `aws_s3_object` | Objet de test (version initiale) |

---

## Prérequis

- AWS CLI configuré avec le profil `training`
- Terraform >= 1.0

---

## Déploiement

```bash
cp terraform.tfvars.example terraform.tfvars
# Remplir terraform.tfvars avec account_id et bucket_name

terraform init
terraform plan
terraform apply
```

## Teardown

```bash
# Vider le bucket avant destroy (obligatoire car versioning actif)
aws s3api delete-objects \
  --bucket tp6-ops-student-792390865255 \
  --delete "$(aws s3api list-object-versions \
    --bucket tp6-ops-student-792390865255 \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json --profile training)" \
  --profile training

terraform destroy
```

---

## Securite appliquee

- **Blocage public** : `BlockPublicAcls`, `IgnorePublicAcls`, `RestrictPublicBuckets` activés
- **Chiffrement AES-256** : appliqué automatiquement à chaque objet uploadé
- **TLS obligatoire** : toute requête HTTP est refusée via `aws:SecureTransport = false`
- **Versioning** : chaque modification crée une nouvelle version — restauration possible à tout moment

---

## Lifecycle rule

| Etape | Jour | Classe de stockage | Cout relatif |
|---|---|---|---|
| Upload | J0 | STANDARD | Référence |
| Transition 1 | J30 | STANDARD_IA | -40% |
| Transition 2 | J90 | GLACIER | -80% |
| Expiration | J365 | Suppression | — |
| Versions non courantes | J+30 | Suppression | — |

---

## Preuves de validation

### 1. Blocage public actif

```json
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": false,
        "RestrictPublicBuckets": true
    }
}
```

---

### 2. Versioning actif

```json
{
    "Status": "Enabled"
}
```

---

### 3. Chiffrement AES-256 par défaut

```json
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }
}
```

---

### 4. Bucket Policy TLS obligatoire

```json
{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "DenyNonTLS",
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:*",
        "Resource": [
            "arn:aws:s3:::tp6-ops-student-792390865255",
            "arn:aws:s3:::tp6-ops-student-792390865255/*"
        ],
        "Condition": {
            "Bool": {
                "aws:SecureTransport": "false"
            }
        }
    }]
}
```

---

### 5. Lifecycle rule configurée

```json
{
    "Rules": [{
        "ID": "tp6-lifecycle",
        "Status": "Enabled",
        "Transitions": [
            { "Days": 30, "StorageClass": "STANDARD_IA" },
            { "Days": 90, "StorageClass": "GLACIER" }
        ],
        "Expiration": { "Days": 365 },
        "NoncurrentVersionExpiration": { "NoncurrentDays": 30 }
    }]
}
```

---

### 6. Deux versions du même objet prouvées

Version 2 uploadée manuellement par-dessus la version 1 :

```
-------------------------------------------------------------------------------
|                             ListObjectVersions                              |
+----------+-----------------------------+------------------------------------+
| IsLatest |        LastModified         |             VersionId              |
+----------+-----------------------------+------------------------------------+
|  True    |  2026-02-26T10:57:22+00:00  |  QQznYT1R3m9.dp.fhxQz_Kje8Szn2fYq  |
|  False   |  2026-02-26T10:53:38+00:00  |  i8Eaf32JeiHMAo7XCp.DkKwpphFqYERd  |
+----------+-----------------------------+------------------------------------+
```

---

### 7. Restauration de la version 1

Copie de la version `i8Eaf32JeiHMAo7XCp.DkKwpphFqYERd` par-dessus la version courante :

```json
{
    "CopySourceVersionId": "i8Eaf32JeiHMAo7XCp.DkKwpphFqYERd",
    "VersionId": "xamXuEzYpYG5AueYyktf5nwrXIDYdxVo",
    "ServerSideEncryption": "AES256"
}
```

Contenu du fichier après restauration :

```
Version 1 - contenu initial - TP6
```

3 versions visibles après restauration (v1 originale, v2, v1 restaurée) :

```
+----------+-----------------------------+------------------------------------+
| IsLatest |        LastModified         |             VersionId              |
+----------+-----------------------------+------------------------------------+
|  True    |  2026-02-26T10:58:02+00:00  |  xamXuEzYpYG5AueYyktf5nwrXIDYdxVo  |  ← v1 restaurée
|  False   |  2026-02-26T10:57:22+00:00  |  QQznYT1R3m9.dp.fhxQz_Kje8Szn2fYq  |  ← v2
|  False   |  2026-02-26T10:53:38+00:00  |  i8Eaf32JeiHMAo7XCp.DkKwpphFqYERd  |  ← v1 originale
+----------+-----------------------------+------------------------------------+
```

> La restauration crée une **nouvelle version** avec le contenu de l'ancienne — l'historique complet est conservé.
