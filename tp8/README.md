# TP8 - DynamoDB : Modélisation par requêtes, GSI, TTL, Streams

> Objectif : Concevoir une table DynamoDB orientée requêtes, éviter le Scan,
> mettre en place un GSI, une politique TTL et activer les Streams.

> 📁 Les captures d'écran des preuves de déploiement sont disponibles
> dans le dossier [docs/](docs/).

---

## Design des clés

### Cas d'usage
Gestion de commandes : chaque commande appartient à un utilisateur,
possède un statut et une date de création.

### Modèle de clés

| Attribut     | Rôle            | Exemple                        |
|--------------|-----------------|--------------------------------|
| `PK`         | Partition Key   | `USER#1`                       |
| `SK`         | Sort Key        | `ORDER#2026-02-01#001`         |
| `status`     | Attribut métier | `PENDING` / `SHIPPED` / `DONE` |
| `created_at` | Date création   | `2026-02-01`                   |
| `expires_at` | TTL (Unix)      | `1740700800`                   |

### Mapping requêtes → patterns d'accès

| Requête cible                         | Méthode | Index utilisé      |
|---------------------------------------|---------|--------------------|
| Toutes les commandes d'un utilisateur | `Query` | Table principale   |
| Commandes par statut                  | `Query` | GSI `status-index` |
| Commandes par date                    | `Query` | SK range `>=`      |

> Aucun `Scan` utilisé — 100% Query sur clés dimensionnées selon les patterns
> d'accès, pas selon un modèle relationnel.

---

## Infrastructure Terraform

### Ressources déployées

- Table DynamoDB `tp8-orders` en mode `PAY_PER_REQUEST`
- GSI `status-index` (PK: `status`, SK: `created_at`, projection: `ALL`)
- TTL activé sur attribut `expires_at`
- Streams activés en mode `NEW_AND_OLD_IMAGES`

### Commandes de déploiement

    terraform init
    terraform plan
    terraform apply

### Outputs

    gsi_name   = "status-index"
    table_name = "tp8-orders"
    table_arn  = "arn:aws:dynamodb:eu-west-3:792390865255:table/tp8-orders"
    stream_arn = "arn:aws:dynamodb:eu-west-3:792390865255:table/tp8-orders/stream/2026-02-27T09:48:34.311"

---

## Insertion des données (10 items)

    for ($i=1; $i -le 10; $i++) {
      aws dynamodb put-item `
        --table-name tp8-orders `
        --item file://items/item$i.json `
        --profile training
    }

Les 10 items couvrent 5 utilisateurs (USER#1 à USER#5),
3 statuts (PENDING, SHIPPED, DONE) et des dates de février 2026.

---

## Requêtes de validation

### Query 1 — Commandes d'un utilisateur (table principale)

    aws dynamodb query \
      --table-name tp8-orders \
      --key-condition-expression "PK = :pk" \
      --expression-attribute-values '{":pk":{"S":"USER#1"}}' \
      --profile training

Résultat :

    {
      "Items": [
        { "PK": {"S": "USER#1"}, "SK": {"S": "ORDER#2026-02-01#001"},
          "product": {"S": "Laptop"}, "status": {"S": "PENDING"},
          "created_at": {"S": "2026-02-01"}, "amount": {"N": "1200"} },
        { "PK": {"S": "USER#1"}, "SK": {"S": "ORDER#2026-02-10#002"},
          "product": {"S": "Mouse"}, "status": {"S": "SHIPPED"},
          "created_at": {"S": "2026-02-10"}, "amount": {"N": "30"} },
        { "PK": {"S": "USER#1"}, "SK": {"S": "ORDER#2026-02-20#003"},
          "product": {"S": "Keyboard"}, "status": {"S": "DONE"},
          "created_at": {"S": "2026-02-20"}, "amount": {"N": "80"} }
      ],
      "Count": 3,
      "ScannedCount": 3
    }

> ✅ 3 commandes retournées pour USER#1 — aucun Scan

### Query 2 — Commandes par statut via GSI

    aws dynamodb query \
      --table-name tp8-orders \
      --index-name status-index \
      --key-condition-expression "#s = :status" \
      --expression-attribute-names '{"#s":"status"}' \
      --expression-attribute-values '{":status":{"S":"PENDING"}}' \
      --profile training

Résultat :

    {
      "Items": [
        { "PK": {"S": "USER#1"}, "SK": {"S": "ORDER#2026-02-01#001"},
          "product": {"S": "Laptop"}, "status": {"S": "PENDING"},
          "created_at": {"S": "2026-02-01"}, "amount": {"N": "1200"} },
        { "PK": {"S": "USER#2"}, "SK": {"S": "ORDER#2026-02-05#004"},
          "product": {"S": "Monitor"}, "status": {"S": "PENDING"},
          "created_at": {"S": "2026-02-05"}, "amount": {"N": "350"} },
        { "PK": {"S": "USER#3"}, "SK": {"S": "ORDER#2026-02-18#007"},
          "product": {"S": "Desk"}, "status": {"S": "PENDING"},
          "created_at": {"S": "2026-02-18"}, "amount": {"N": "400"} },
        { "PK": {"S": "USER#5"}, "SK": {"S": "ORDER#2026-02-27#010"},
          "product": {"S": "Temporary Item"}, "status": {"S": "PENDING"},
          "created_at": {"S": "2026-02-27"}, "expires_at": {"N": "1740700800"},
          "amount": {"N": "10"} }
      ],
      "Count": 4,
      "ScannedCount": 4
    }

> ✅ 4 commandes PENDING via GSI status-index — dont l'item éphémère USER#5

### Query 3 — Commandes par date (SK range)

    aws dynamodb query \
      --table-name tp8-orders \
      --key-condition-expression "PK = :pk AND SK >= :date" \
      --expression-attribute-values '{":pk":{"S":"USER#1"},":date":{"S":"ORDER#2026-02-10"}}' \
      --profile training

Résultat :

    {
      "Items": [
        { "PK": {"S": "USER#1"}, "SK": {"S": "ORDER#2026-02-10#002"},
          "product": {"S": "Mouse"}, "status": {"S": "SHIPPED"},
          "created_at": {"S": "2026-02-10"}, "amount": {"N": "30"} },
        { "PK": {"S": "USER#1"}, "SK": {"S": "ORDER#2026-02-20#003"},
          "product": {"S": "Keyboard"}, "status": {"S": "DONE"},
          "created_at": {"S": "2026-02-20"}, "amount": {"N": "80"} }
      ],
      "Count": 2,
      "ScannedCount": 2
    }

> ✅ 2 commandes de USER#1 à partir du 10 février — tri par SK garanti

---

## TTL — Items éphémères

TTL activé sur l'attribut `expires_at` (timestamp Unix).

    aws dynamodb describe-time-to-live \
      --table-name tp8-orders \
      --profile training

Résultat :

    {
      "TimeToLiveDescription": {
        "TimeToLiveStatus": "ENABLED",
        "AttributeName": "expires_at"
      }
    }

L'item USER#5 / ORDER#2026-02-27#010 possède un expires_at = 1740700800
(~28 février 2026) et sera automatiquement supprimé par DynamoDB à expiration.

---

## Streams — Préparation intégration Lambda

Streams activés en mode `NEW_AND_OLD_IMAGES` : chaque modification
(création, mise à jour, suppression) génère un événement contenant
l'ancienne et la nouvelle image de l'item.

    aws dynamodb describe-table \
      --table-name tp8-orders \
      --profile training \
      --query "Table.{StreamEnabled:StreamSpecification.StreamEnabled,StreamArn:LatestStreamArn,StreamViewType:StreamSpecification.StreamViewType}"

Résultat :

    {
      "StreamEnabled": true,
      "StreamArn": "arn:aws:dynamodb:eu-west-3:792390865255:table/tp8-orders/stream/2026-02-27T09:48:34.311",
      "StreamViewType": "NEW_AND_OLD_IMAGES"
    }

---

## Structure du projet

    tp8/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── items/
    │   ├── item1.json
    │   ├── item2.json
    │   └── item10.json
    └── docs/
        ├── Terraform_Apply.png
        ├── TTL_Config.png
        └── Stream_Config.png
