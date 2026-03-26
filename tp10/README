# TP10 - API Gateway, SQS, DLQ : pipeline asynchrone robuste

> Objectif : Exposer une API, valider une requête, publier en queue,
> traiter et persister. Prouver la gestion d'échec via DLQ.


---

## Architecture

    POST /items (API Gateway HTTP)
          │
          ▼
    Lambda tp10-validator
    ├── Valide payload (user_id, product, amount obligatoires)
    ├── Cas valide   → envoie message dans SQS tp10-queue
    └── Cas invalide → retourne 400 + raison loggée

    SQS tp10-queue (redrive: 3 tentatives max)
          │                        ❌ échec × 3
          ▼                              │
    Lambda tp10-consumer                 ▼
    ├── Consomme message SQS        SQS tp10-dlq
    └── Écrit item dans DynamoDB

    DynamoDB tp8-orders
    └── PK = user_id / SK = ORDER#<item_id>

---

## Rôles IAM minimaux

### tp10-validator-role

| Permission | Ressource ciblée |
|---|---|
| `sqs:SendMessage` | `arn:aws:sqs:::tp10-queue` |
| `logs:*` | `/aws/lambda/tp10-validator` |

### tp10-consumer-role

| Permission | Ressource ciblée |
|---|---|
| `sqs:ReceiveMessage` `sqs:DeleteMessage` `sqs:GetQueueAttributes` | `arn:aws:sqs:::tp10-queue` |
| `dynamodb:PutItem` | `arn:aws:dynamodb:::table/tp8-orders` |
| `logs:*` | `/aws/lambda/tp10-consumer` |

---

## Infrastructure Terraform

### Ressources déployées (16)

- SQS queue `tp10-queue` (visibility timeout 30s, retention 24h)
- SQS DLQ `tp10-dlq` (redrive policy : maxReceiveCount = 3)
- IAM Role + Policy `tp10-validator-role`
- IAM Role + Policy `tp10-consumer-role`
- Lambda `tp10-validator` (Python 3.12, 128 MB, timeout 10s)
- Lambda `tp10-consumer` (Python 3.12, 128 MB, timeout 30s)
- CloudWatch Log Group `/aws/lambda/tp10-validator` (7 jours)
- CloudWatch Log Group `/aws/lambda/tp10-consumer` (7 jours)
- Event Source Mapping SQS → tp10-consumer (batch size 1)
- API Gateway HTTP `tp10-api`
- Stage `$default` avec auto-deploy
- Integration AWS_PROXY → tp10-validator
- Route `POST /items`
- Permission `lambda:InvokeFunction` pour API Gateway

### Commandes de déploiement

    terraform init
    terraform plan
    terraform apply

### Outputs

    api_endpoint   = "https://mlt152umse.execute-api.eu-west-3.amazonaws.com/"
    queue_url      = "https://sqs.eu-west-3.amazonaws.com/792390865255/tp10-queue"
    dlq_url        = "https://sqs.eu-west-3.amazonaws.com/792390865255/tp10-dlq"
    validator_name = "tp10-validator"
    consumer_name  = "tp10-consumer"

---

## Tests de validation

### Test 1 — Cas nominal (requête valide)

    Invoke-RestMethod -Method POST \
      -Uri "https://mlt152umse.execute-api.eu-west-3.amazonaws.com/items" \
      -ContentType "application/json" \
      -Body '{"user_id": "USER#11", "product": "Monitor", "amount": 350}'

Résultat :

    item_id                              status
    -------                              ------
    27813412-2e3a-48d2-b062-07545fecb234 QUEUED

### Vérification DynamoDB

    aws dynamodb query \
      --table-name tp8-orders \
      --key-condition-expression "PK = :pk" \
      --expression-attribute-values '{":pk":{"S":"USER#11"}}' \
      --profile training

Résultat :

    {
      "Items": [
        {
          "product":    {"S": "Monitor"},
          "item_id":    {"S": "27813412-2e3a-48d2-b062-07545fecb234"},
          "request_id": {"S": "a4a6a919-ea8a-4cb7-a7ff-a539a2f1fa50"},
          "status":     {"S": "PROCESSED"},
          "amount":     {"N": "350"},
          "PK":         {"S": "USER#11"},
          "SK":         {"S": "ORDER#27813412-2e3a-48d2-b062-07545fecb234"}
        }
      ],
      "Count": 1,
      "ScannedCount": 1
    }

> ✅ Item créé et traçable en DynamoDB — pipeline nominal validé

### Test 2 — Cas invalide (champs manquants)

    Invoke-RestMethod -Method POST \
      -Uri "https://mlt152umse.execute-api.eu-west-3.amazonaws.com/items" \
      -ContentType "application/json" \
      -Body '{"user_id": "USER#10"}'

Résultat :

    {"error": "Champs manquants : ['product', 'amount']"}

> ✅ Requête rejetée avec HTTP 400 — aucun message envoyé en SQS

### Test 3 — Cas DLQ (erreur forcée)

Activation du mode erreur :

    aws lambda update-function-configuration \
      --function-name tp10-consumer \
      --environment "Variables={DYNAMODB_TABLE=tp8-orders,FORCE_ERROR=true}" \
      --profile training

Envoi d'un item test :

    Invoke-RestMethod -Method POST \
      -Uri "https://mlt152umse.execute-api.eu-west-3.amazonaws.com/items" \
      -ContentType "application/json" \
      -Body '{"user_id": "USER#99", "product": "TestDLQ", "amount": 1}'

Résultat :

    item_id                              status
    -------                              ------
    5d199f30-22c3-489d-b558-abbf13e13f35 QUEUED

Après 3 tentatives échouées (~2 minutes), vérification DLQ :

    aws sqs receive-message \
      --queue-url "https://sqs.eu-west-3.amazonaws.com/792390865255/tp10-dlq" \
      --max-number-of-messages 5 \
      --profile training

Résultat :

    {
      "Messages": [{
        "MessageId": "24a872a0-bfdc-475e-81cc-3dbdaa821714",
        "Body": {
          "item_id":    "5d199f30-22c3-489d-b558-abbf13e13f35",
          "user_id":    "USER#99",
          "product":    "TestDLQ",
          "amount":     1,
          "request_id": "3d140c45-9e8a-4dab-a78f-09dd5a9e354b",
          "status":     "PENDING"
        }
      }]
    }

> ✅ Message en DLQ après 3 tentatives — gestion d'échec validée

---

## Logs CloudWatch

### tp10-validator — cas nominal + cas invalide

    START RequestId: 0e5e1ab8 Version: $LATEST
    [INFO]  {"request_id": "0e5e1ab8", "status": "QUEUED",
             "item_id": "0d2d1bd1-8ac4-4190-9115-c1778d58090c"}
    REPORT  Duration: 286.85 ms   Billed Duration: 696 ms
            Memory Size: 128 MB   Max Memory Used: 86 MB

    START RequestId: 695e9e1d Version: $LATEST
    [ERROR] {"request_id": "695e9e1d", "status": "REJECTED",
             "reason": "Champs manquants : ['product', 'amount']"}
    REPORT  Duration: 2.90 ms   Billed Duration: 3 ms
            Memory Size: 128 MB   Max Memory Used: 86 MB

### tp10-consumer — cas nominal

    START RequestId: ca3cce04 Version: $LATEST
    [INFO]  {"request_id": "ca3cce04", "status": "PROCESSING",
             "item_id": "0d2d1bd1-8ac4-4190-9115-c1778d58090c"}
    [INFO]  {"request_id": "ca3cce04", "status": "PROCESSED",
             "item_id": "0d2d1bd1-8ac4-4190-9115-c1778d58090c"}
    REPORT  Duration: 287.07 ms   Billed Duration: 715 ms
            Memory Size: 128 MB   Max Memory Used: 89 MB

---

## Structure du projet

    tp10/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    └── lambda/
        ├── validator.py
        └── consumer.py
