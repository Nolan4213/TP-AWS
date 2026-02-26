# TP AWS - Infrastructure as Code

Travaux pratiques AWS realises en Terraform.

## Structure

| Dossier | Description |
|---|---|
| tp5/ | ALB + ASG multi-AZ haute disponibilite |
| tp6/ | S3 securite - versioning, TLS, chiffrement, lifecycle |

## Prerequis

- AWS CLI configure avec profil training
- Terraform >= 1.0

## Utilisation

    cd tp5/   # ou tp6/
    cp terraform.tfvars.example terraform.tfvars
    terraform init
    terraform plan
    terraform apply