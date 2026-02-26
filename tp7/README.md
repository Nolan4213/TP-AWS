# TP7 — RDS Privé : SG restrictif, chiffrement, snapshot et restauration

> **Objectif** : Déployer une base PostgreSQL managée en privé, prouver l'accès
> applicatif via un Security Group restrictif, mettre en œuvre les sauvegardes
> et documenter une restauration complète.

---

## Architecture

```
Internet
   │
   │  (accès refusé depuis l'extérieur — SG bloque tout)
   │
[Session Manager — sans IP publique ni clé SSH]
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│  VPC tp3-vpc — 10.0.0.0/16 (vpc-081cb4f820f7e2c22)      │
│                                                          │
│  ┌──────────────────────┐       ┌─────────────────────┐  │
│  │ tp4-app              │──────►│ RDS PostgreSQL      │  │
│  │ sg-0259f1245c37aa816 │ :5432 │ tp7-postgres        │  │
│  │ subnet 10.0.10.0/24  │       │ sg-057e0e1bfae62d340│  │
│  └──────────────────────┘       │ subnet 10.0.10.0/24 │  │
│                                 │ subnet 10.0.11.0/24 │  │
│                                 └─────────────────────┘  │
└──────────────────────────────────────────────────────────┘

Règle SG RDS : ingress port 5432 UNIQUEMENT depuis sg-0259f1245c37aa816
```

---

## Ressources Terraform

| Ressource | Nom | Description |
|---|---|---|
| `aws_db_subnet_group` | tp7-db-subnet-group | Subnets privés multi-AZ |
| `aws_security_group` | tp7-sg-rds | Ingress 5432 depuis SG app uniquement |
| `aws_db_instance` | tp7-postgres | PostgreSQL 16.6, db.t3.micro, chiffré |

---

## Prérequis

- VPC TP3 (`vpc-081cb4f820f7e2c22`)
- Instance `tp4-app` (`i-0a36bac6f9c5d0bd5`) avec rôle SSM
- AWS CLI configuré avec le profil `training`
- Terraform >= 1.0

---

## Déploiement

```bash
terraform init
terraform plan
terraform apply
```

> ⏱️ La création RDS prend environ 5 à 10 minutes.

## Teardown

```powershell
# Supprimer les snapshots manuels avant le destroy
aws rds delete-db-snapshot `
  --db-snapshot-identifier tp7-snapshot-manuel `
  --profile training

# Supprimer l'instance restaurée
aws rds delete-db-instance `
  --db-instance-identifier tp7-postgres-restored `
  --skip-final-snapshot `
  --profile training

terraform destroy
```

> ⚠️ Les snapshots manuels et l'instance restaurée **survivent au terraform destroy** — les supprimer manuellement pour éviter des frais.

---

## Sécurité appliquée

- **Accès public désactivé** : `publicly_accessible = false`
- **SG restrictif** : port 5432 autorisé uniquement depuis `sg-0259f1245c37aa816` — toute autre source est bloquée
- **Chiffrement au repos** : `storage_encrypted = true` (AES-256, clé KMS)
- **Transport chiffré** : connexion SSL TLSv1.3 active à chaque connexion
- **Sauvegardes automatiques** : rétention 7 jours, fenêtre 02h00-03h00 UTC

---

## DB Subnet Group

| AZ | Subnet ID | CIDR |
|---|---|---|
| eu-west-3a | subnet-06a2e1634b5a61540 | 10.0.10.0/24 |
| eu-west-3b | subnet-03ea0b0c3df7883a0 | 10.0.11.0/24 |

---

## Paramètres RDS

| Paramètre | Valeur |
|---|---|
| Identifiant | tp7-postgres |
| Moteur | PostgreSQL 16.6 |
| Classe | db.t3.micro |
| Stockage | 20 Go gp2 |
| Chiffrement au repos | AES-256 ✅ |
| Clé KMS | arn:aws:kms:eu-west-3:792390865255:key/2fc446a9-... |
| Accès public | Désactivé ✅ |
| Sauvegardes auto | 7 jours ✅ |
| Multi-AZ | Non (TP) |
| VPC | vpc-081cb4f820f7e2c22 |
| SG | sg-057e0e1bfae62d340 |

---

## Preuves de validation

### 1. Connexion RDS depuis tp4-app

Connexion établie via Session Manager sans IP publique ni clé SSH :

```
psql -h tp7-postgres.cpai0qcwim1j.eu-west-3.rds.amazonaws.com -U admintp7 -d tp7db -p 5432
Password for user admintp7:
psql (15.15, server 16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
tp7db=>
```

![Connexion RDS](docs/Connexion_BDD.png)

---

### 2. Requêtes SQL de preuve

```sql
-- Création de la table
CREATE TABLE tp7_proof (
    id SERIAL PRIMARY KEY,
    message VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insertion des données
INSERT INTO tp7_proof (message) VALUES
    ('Connexion RDS depuis tp4-app via SG restrictif'),
    ('Chiffrement AES-256 actif'),
    ('Transport TLS 1.3 confirme');

-- Lecture
SELECT * FROM tp7_proof;

-- Version serveur
SELECT version();

-- SSL actif
SHOW ssl;
```

![Requêtes SQL](docs/Requêtes_BDD.png)

---

### 3. Connexion depuis réseau non autorisé = impossible

Tentative depuis un poste extérieur au VPC — le SG RDS bloque toute source
autre que `sg-0259f1245c37aa816`, la connexion timeout sans réponse.

---

### 4. Snapshot manuel

```powershell
aws rds create-db-snapshot `
  --db-instance-identifier tp7-postgres `
  --db-snapshot-identifier tp7-snapshot-manuel `
  --profile training
```

- **ARN** : `arn:aws:rds:eu-west-3:792390865255:snapshot:tp7-snapshot-manuel`
- **Type** : manual
- **Chiffré** : true (même clé KMS que l'instance source)
- **Status** : available

![Snapshot](docs/Snapshot_BDD.png)

---

## Procédure de restauration

### Étape 1 — Restaurer depuis le snapshot

```powershell
aws rds restore-db-instance-from-db-snapshot `
  --db-instance-identifier tp7-postgres-restored `
  --db-snapshot-identifier tp7-snapshot-manuel `
  --db-subnet-group-name tp7-db-subnet-group `
  --vpc-security-group-ids sg-057e0e1bfae62d340 `
  --no-publicly-accessible `
  --profile training
```

### Étape 2 — Attendre la disponibilité

```powershell
aws rds describe-db-instances `
  --db-instance-identifier tp7-postgres-restored `
  --profile training `
  --query "DBInstances.{Status:DBInstanceStatus,Endpoint:Endpoint.Address}" `
  --output table
```

### Étape 3 — Connexion et vérification post-restauration

Depuis tp4-app via Session Manager :

```bash
psql -h tp7-postgres-restored.cpai0qcwim1j.eu-west-3.rds.amazonaws.com \
     -U admintp7 -d tp7db -p 5432
```

```sql
-- Vérifier que les données du snapshot sont bien présentes
SELECT * FROM tp7_proof;
```

![Preuve restauration](docs/Preuve_données_restauré.png)

> ✅ Les 3 lignes de `tp7_proof` sont présentes dans l'instance restaurée —
> la restauration est validée.

![Connexion instance restaurée](docs/Connexion_BDD_Restore.png)
