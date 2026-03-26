# TP12 - KMS, Secrets Manager, GuardDuty

> Objectif : Chiffrer les données avec une clé KMS dédiée, consommer
> un secret au runtime via rôle applicatif, et activer la détection
> de menaces GuardDuty.


---

## Architecture

    Lambda tp10-consumer
    ├── Au démarrage : appel Secrets Manager (GetSecretValue)
    │     └── Déchiffrement via KMS tp12-key (kms:Decrypt)
    │           └── Retourne {username, password, host, port, dbname}
    ├── Traitement SQS → écriture DynamoDB tp8-orders
    └── Logs : db_host + db_user loggés / password jamais exposé

    S3 tp6-training-792390865255
    └── Chiffrement SSE-KMS → clé tp12-key (BucketKey activé)

    GuardDuty tp12-detector
    └── Management events + S3 logs supervisés

---

## Infrastructure Terraform

### Ressources déployées

- KMS Key `alias/tp12-key` (rotation annuelle, deletion window 7j)
- KMS Key Policy (root, consumer role, SecretsManager, S3)
- S3 SSE-KMS sur `tp6-training-792390865255` (BucketKey enabled)
- Secrets Manager secret `tp12/db-credentials` (chiffré KMS)
- IAM Policy `tp12-consumer-secrets-kms-policy`
- IAM Role Policy Attachment sur `tp10-consumer-role`
- GuardDuty Detector (S3 logs enabled)

### Commandes de déploiement

    terraform init
    terraform apply

### Mise à jour Lambda (hors Terraform — Windows)

    $secretArn = "arn:aws:secretsmanager:eu-west-3:792390865255:secret:tp12/db-credentials-f2FxZH"

    aws lambda update-function-configuration `
      --function-name tp10-consumer `
      --environment "Variables={DYNAMODB_TABLE=tp8-orders,FORCE_ERROR=false,SECRET_ARN=$secretArn}" `
      --profile training

    Compress-Archive -Path lambda\consumer.py -DestinationPath lambda\consumer.zip -Force

    aws lambda update-function-code `
      --function-name tp10-consumer `
      --zip-file fileb://lambda/consumer.zip `
      --profile training

### Outputs

    kms_key_id            = "fdc3227e-1370-4179-82e4-50ffe5a2108f"
    kms_key_arn           = "arn:aws:kms:eu-west-3:792390865255:key/fdc3227e-1370-4179-82e4-50ffe5a2108f"
    kms_alias             = "alias/tp12-key"
    secret_arn            = "arn:aws:secretsmanager:eu-west-3:792390865255:secret:tp12/db-credentials-f2FxZH"
    secret_name           = "tp12/db-credentials"
    guardduty_detector_id = (voir aws guardduty list-detectors)

---

## Clé KMS

### Configuration

| Paramètre | Valeur |
|---|---|
| Alias | `alias/tp12-key` |
| Type | Symétrique (ENCRYPT_DECRYPT) |
| Rotation | Activée (annuelle) |
| Deletion window | 7 jours |
| Usages | S3 SSE, Secrets Manager, Lambda Decrypt |

### Key Policy — principals autorisés

| Principal | Actions |
|---|---|
| `arn:aws:iam::792390865255:root` | `kms:*` (admin) |
| `tp10-consumer-role` | `kms:Decrypt` `kms:DescribeKey` |
| `secretsmanager.amazonaws.com` | `kms:Decrypt` `kms:GenerateDataKey` |
| `s3.amazonaws.com` | `kms:Decrypt` `kms:GenerateDataKey` |

### Vérification

    aws kms describe-key \
      --key-id alias/tp12-key \
      --profile training \
      --query "KeyMetadata.{ID:KeyId,Etat:KeyState,Rotation:KeyRotationStatus}"

---

## Secrets Manager

### Secret `tp12/db-credentials`

    {
      "username": "admin",
      "password": "**redacted**",
      "engine":   "postgres",
      "host":     "tp7-rds.eu-west-3.rds.amazonaws.com",
      "port":     5432,
      "dbname":   "tpdb"
    }

> ✅ Chiffré avec `alias/tp12-key` — aucun secret en clair dans le
> code, les variables d'environnement ou les logs

### IAM Policy minimale attachée à `tp10-consumer-role`

    {
      "Statement": [
        {
          "Sid": "AllowGetSecret",
          "Effect": "Allow",
          "Action": "secretsmanager:GetSecretValue",
          "Resource": "arn:aws:secretsmanager:eu-west-3:792390865255:secret:tp12/db-credentials-f2FxZH"
        },
        {
          "Sid": "AllowKMSDecrypt",
          "Effect": "Allow",
          "Action": ["kms:Decrypt", "kms:DescribeKey"],
          "Resource": "arn:aws:kms:eu-west-3:792390865255:key/fdc3227e-1370-4179-82e4-50ffe5a2108f"
        }
      ]
    }

---

## S3 — Chiffrement KMS

### Vérification

    aws s3api get-bucket-encryption \
      --bucket tp6-training-792390865255 \
      --profile training

Résultat :

    {
      "ServerSideEncryptionConfiguration": {
        "Rules": [{
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm":   "aws:kms",
            "KMSMasterKeyID": "arn:aws:kms:eu-west-3:792390865255:key/fdc3227e-1370-4179-82e4-50ffe5a2108f"
          },
          "BucketKeyEnabled": true
        }]
      }
    }

> ✅ SSE-KMS actif avec clé dédiée — BucketKey activé pour réduire
> les appels KMS et les coûts associés

---

## Test — Secret lu au runtime

Envoi d'un item via l'API :

    Invoke-RestMethod -Method POST \
      -Uri "https://mlt152umse.execute-api.eu-west-3.amazonaws.com/items" \
      -ContentType "application/json" \
      -Body '{"user_id": "USER#TP12", "product": "KMSTest", "amount": 99}'

Résultat :

    item_id                              status
    -------                              ------
    2e08768e-1c71-438c-8a91-acbc0d0cd6d0 QUEUED

Logs CloudWatch du consumer :

    [INFO] {"request_id": "a1140a50-7ab4-5602-b9b1-686ff16d7733",
            "status":     "SECRET_LOADED",
            "db_host":    "tp7-rds.eu-west-3.rds.amazonaws.com",
            "db_user":    "admin"}
            # password absent des logs ✅

    [INFO] {"request_id": "a1140a50-7ab4-5602-b9b1-686ff16d7733",
            "status":     "PROCESSING",
            "item_id":    "2e08768e-1c71-438c-8a91-acbc0d0cd6d0"}

> ✅ Secret récupéré dynamiquement au runtime via KMS
> Password jamais exposé dans les logs ni les variables visibles

---

## GuardDuty

### État du détecteur

    aws guardduty list-detectors --profile training

    aws guardduty get-detector \
      --detector-id <detector-id> \
      --profile training \
      --query "{Status:Status,CreatedAt:CreatedAt,S3Logs:DataSources.S3Logs.Status}"

Résultat :

    {
      "Status":    "ENABLED",
      "CreatedAt": "2026-03-26T19:15:01.309Z",
      "S3Logs":    "ENABLED"
    }

### Findings

    aws guardduty list-findings \
      --detector-id <detector-id> \
      --profile training

Résultat :

    {"FindingIds": []}

> ✅ Aucune menace détectée — attendu sur un compte de TP propre
> GuardDuty nécessite 24-48h pour générer des findings sur un compte
> actif. Les catégories supervisées : accès S3 anormaux, appels API
> suspects, reconnaissance réseau, credentials compromis.

### Catégories de findings GuardDuty

| Catégorie | Exemple de finding |
|---|---|
| Reconnaissance | `Recon:IAMUser/MaliciousIPCaller` |
| Credentials compromis | `UnauthorizedAccess:IAMUser/ConsoleLogin` |
| Accès S3 suspect | `Discovery:S3/MaliciousIPCaller` |
| Exfiltration | `Exfiltration:S3/ObjectRead.Unusual` |

---

## Structure du projet

    tp12/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── lambda/
        └── consumer.py   # version avec lecture secret au runtime
