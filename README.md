# TP AWS - Infrastructure as Code

Travaux pratiques AWS réalisés en Terraform.

## Structure

| Dossier | Description |
|---------|-------------|
| `tp5/`  | ALB + ASG multi-AZ haute disponibilité |
| `tp6/`  | S3 sécurité - versioning, TLS, chiffrement, lifecycle |
| `tp7/`  | RDS privée - SG restrictif, chiffrement, snapshot et restauration |
| `tp8/`  | DynamoDB - modélisation par requêtes, GSI, TTL, Streams |
| `tp9/`  | Lambda + API Gateway - serverless REST API avec DynamoDB |
| `tp10/` | API Gateway + SQS + DLQ + Lambda - pipeline asynchrone robuste |

## Pré-requis

- AWS CLI configuré avec profil `training`
- Terraform >= 1.0

## Utilisation

    cd tp5/   # ou tp6/ tp7/ tp8/ tp9/ tp10/
    cp terraform.tfvars.example terraform.tfvars
    terraform init
    terraform plan
    terraform apply
