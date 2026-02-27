# TP AWS - Infrastructure as Code

Travaux pratiques AWS realisés en Terraform.
Vous trouverez les document nécessaires fichier .tf, captures d'écran...
## Structure

| Dossier | Description |
|---|---|
| tp5/ | ALB + ASG multi-AZ haute disponibilite |
| tp6/ | S3 securite - versioning, TLS, chiffrement, lifecycle |
| tp7/ | RDS prive - SG restrictif, chiffrement, snapshot et restauration |

## Prerequis

- AWS CLI configure avec profil training
- Terraform >= 1.0

## Utilisation

```bash
cd tp5/   # ou tp6/ ou tp7/
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```
