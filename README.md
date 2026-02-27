# TP AWS - Infrastructure as Code

Travaux pratiques AWS réalisés en Terraform.

## Structure

| Dossier | Description |
|---------|-------------|
| `tp5/`  | ALB + ASG multi-AZ haute disponibilité |
| `tp6/`  | S3 sécurité - versioning, TLS, chiffrement, lifecycle |
| `tp7/`  | RDS privée - SG restrictif, chiffrement, snapshot et restauration |
| `tp8/`  | DynamoDB - modélisation par requêtes, GSI, TTL, Streams |

## Pré-requis

- AWS CLI configuré avec profil `training`
- Terraform >= 1.0

## Utilisation

    cd tp5/   # ou tp6/ ou tp7/ ou tp8/
    cp terraform.tfvars.example terraform.tfvars
    terraform init
    terraform plan
    terraform apply
