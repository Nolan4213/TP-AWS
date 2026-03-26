# TP11 - Observabilité CloudWatch, CloudTrail, Flow Logs, alarmes

> Objectif : Mettre en place une supervision minimale exploitable et une
> traçabilité des actions sur le pipeline asynchrone TP10.

> 📁 Les captures d'écran des preuves de déploiement sont disponibles
> dans le dossier [docs/](docs/).

---

## Architecture supervisée

    POST /items (API Gateway)
          │
          ▼
    Lambda tp10-validator ──────────────────────────┐
          │                                         │
          ▼                                         │
    SQS tp10-queue                           CloudWatch
          │              ❌ échec × 3         ├── Dashboard tp11-pipeline-observability
          ▼                   │               ├── Alarme DLQ non vide
    Lambda tp10-consumer      ▼               ├── Alarme Lambda errors
          │             SQS tp10-dlq          ├── Alarme API GW 5xx
          ▼                                   └── Alarme Throttles
    DynamoDB tp8-orders
                                    CloudTrail tp11-trail
                                    └── S3 tp11-cloudtrail-792390865255

    VPC tp3-flowlogs
    └── /vpc/tp3-flowlogs (ENIs supervisées)

---

## Infrastructure Terraform

### Ressources déployées

- CloudWatch Dashboard `tp11-pipeline-observability` (8 widgets)
- CloudWatch Alarm `tp11-alarm-dlq-not-empty`
- CloudWatch Alarm `tp11-alarm-lambda-consumer-errors`
- CloudWatch Alarm `tp11-alarm-apigw-5xx`
- CloudWatch Alarm `tp11-alarm-lambda-throttles`
- S3 Bucket `tp11-cloudtrail-792390865255` (logs CloudTrail)
- S3 Bucket Policy (autorisation CloudTrail write)
- CloudTrail `tp11-trail` (management events, validation activée)

### Commandes de déploiement

    terraform init
    terraform plan
    terraform apply

### Outputs

    dashboard_url       = "https://eu-west-3.console.aws.amazon.com/cloudwatch/home?region=eu-west-3#dashboards:name=tp11-pipeline-observability"
    alarm_dlq           = "tp11-alarm-dlq-not-empty"
    alarm_lambda_errors = "tp11-alarm-lambda-consumer-errors"
    alarm_apigw_5xx     = "tp11-alarm-apigw-5xx"
    cloudtrail_name     = "tp11-trail"
    cloudtrail_bucket   = "tp11-cloudtrail-792390865255"

---

## Dashboard CloudWatch

### Widgets configurés (8)

| Widget | Métrique | Namespace | Stat |
|---|---|---|---|
| Lambda consumer — Erreurs | `Errors` | `AWS/Lambda` | Sum |
| Lambda — Durée (ms) | `Duration` | `AWS/Lambda` | Average |
| DLQ — Messages visibles | `ApproximateNumberOfMessagesVisible` | `AWS/SQS` | Maximum |
| API Gateway — 5xx | `5XXError` | `AWS/ApiGateway` | Sum |
| API Gateway — Latence p99 | `Latency` | `AWS/ApiGateway` | p99 |
| SQS queue — Messages en attente | `ApproximateNumberOfMessagesVisible` | `AWS/SQS` | Maximum |
| Lambda — Throttles | `Throttles` | `AWS/Lambda` | Sum |
| Lambda — Invocations | `Invocations` | `AWS/Lambda` | Sum |

---

## Alarmes CloudWatch

### Configuration

| Alarme | Métrique | Seuil | Période | Justification |
|---|---|---|---|---|
| `tp11-alarm-dlq-not-empty` | DLQ `ApproximateNumberOfMessagesVisible` | > 0 | 60s | Tout message en DLQ indique un échec non résolu |
| `tp11-alarm-lambda-consumer-errors` | Lambda `Errors` | > 0 | 60s | Erreur d'exécution Lambda anormale |
| `tp11-alarm-apigw-5xx` | API GW `5XXError` | > 0 | 60s | Erreur serveur côté validator |
| `tp11-alarm-lambda-throttles` | Lambda `Throttles` | > 0 | 60s | Saturation de la concurrence Lambda |

### Vérification des états

    aws cloudwatch describe-alarms \
      --alarm-names "tp11-alarm-dlq-not-empty" "tp11-alarm-lambda-consumer-errors" \
      --profile training \
      --query "MetricAlarms[*].{Nom:AlarmName,Etat:StateValue,Raison:StateReason}"

---

## Test 1 — Déclenchement contrôlé alarme DLQ

Activation du mode erreur sur le consumer :

    aws lambda update-function-configuration \
      --function-name tp10-consumer \
      --environment "Variables={DYNAMODB_TABLE=tp8-orders,FORCE_ERROR=true}" \
      --profile training

Envoi d'un item déclencheur :

    Invoke-RestMethod -Method POST \
      -Uri "https://mlt152umse.execute-api.eu-west-3.amazonaws.com/items" \
      -ContentType "application/json" \
      -Body '{"user_id": "USER#TP11", "product": "AlarmTest", "amount": 1}'

Résultat après 3 tentatives (~2 minutes) :

    [
      {
        "Nom": "tp11-alarm-dlq-not-empty",
        "Etat": "ALARM",
        "Raison": "Threshold Crossed: 1 datapoint [1.0 (26/03/26 09:42:00)] was greater than the threshold (0.0)."
      },
      {
        "Nom": "tp11-alarm-lambda-consumer-errors",
        "Etat": "OK",
        "Raison": "Threshold Crossed: no datapoints were received for 1 period and 1 missing datapoint was treated as [NonBreaching]."
      }
    ]

> ✅ Alarme DLQ déclenchée en ALARM — supervision opérationnelle validée
>
> ℹ️ L'alarme Lambda errors reste OK : FORCE_ERROR lève une exception
> Python capturée par SQS comme échec de batch, non comptabilisée
> dans la métrique Lambda Errors. C'est la DLQ qui est le signal
> fiable en production.

Remise en état nominal :

    aws lambda update-function-configuration \
      --function-name tp10-consumer \
      --environment "Variables={DYNAMODB_TABLE=tp8-orders,FORCE_ERROR=false}" \
      --profile training

---

## Test 2 — CloudTrail : event IAM tracé

    aws cloudtrail lookup-events \
      --lookup-attributes AttributeKey=EventName,AttributeValue=CreateTrail \
      --max-results 3 \
      --profile training \
      --query "Events[*].{Heure:EventTime,Action:EventName,User:Username,Resource:Resources[0].ResourceName}"

Résultat :

    [
      {
        "Heure":    "2026-03-26T10:43:34+01:00",
        "Action":   "CreateTrail",
        "User":     "tp-session",
        "Resource": "arn:aws:cloudtrail:eu-west-3:792390865255:trail/tp11-trail"
      }
    ]

> ✅ CloudTrail a tracé la création de son propre trail
> Identité : tp-session | Action : CreateTrail | Ressource : tp11-trail

---

## Test 3 — Flow Logs : interprétation

Groupe de logs actif depuis TP3 :

    aws logs describe-log-groups \
      --profile training \
      --query "logGroups[?contains(logGroupName, 'flow')].{Nom:logGroupName,Retention:retentionInDays}"

Résultat :

    [{"Nom": "/vpc/tp3-flowlogs", "Retention": null}]

Extraction des entrées récentes :

    aws logs filter-log-events \
      --log-group-name "/vpc/tp3-flowlogs" \
      --start-time ([DateTimeOffset]::UtcNow.AddHours(-2).ToUnixTimeMilliseconds()) \
      --max-items 5 \
      --profile training \
      --query "events[*].message"

Résultat :

    "2 792390865255 eni-09e02120b31abe1ee - - - - - - - 1774511735 1774511820 - NODATA"
    "2 792390865255 eni-04e8d137216bd8ad0 - - - - - - - 1774511747 1774511820 - NODATA"
    "2 792390865255 eni-09e02120b31abe1ee - - - - - - - 1774511750 1774511840 - NODATA"
    "2 792390865255 eni-0c80badf5309e7019 - - - - - - - 1774511758 1774511820 - NODATA"
    "2 792390865255 eni-0c80badf5309e7019 - - - - - - - 1774511768 1774511856 - NODATA"

### Interprétation

| Champ | Valeur | Signification |
|---|---|---|
| `version` | 2 | Format VPC Flow Logs v2 |
| `account_id` | 792390865255 | Compte AWS du projet |
| `interface` | eni-09e02120b31abe1ee | ENI de service managé (NAT, endpoint) |
| `src / dst / ports` | `-` | Non applicable |
| `status` | `NODATA` | Aucun trafic réseau sur la fenêtre |
| `action` | `-` | Aucun flux à évaluer |

> ✅ Flow Logs opérationnels — NODATA attendu : les Lambdas TP10 sont
> hors VPC, donc aucun trafic VPC direct. Les ENIs supervisées
> appartiennent aux services managés AWS (NAT Gateway, VPC endpoints).

---

## Runbook — Triage alarme DLQ

### Contexte

L'alarme `tp11-alarm-dlq-not-empty` se déclenche dès qu'un message
entre dans `tp10-dlq`. Cela indique que le consumer a échoué 3 fois
consécutives sur au moins un message.

### Étapes de triage

**1. Confirmer l'alarme**

    aws cloudwatch describe-alarms \
      --alarm-names "tp11-alarm-dlq-not-empty" \
      --profile training \
      --query "MetricAlarms[0].{Etat:StateValue,Raison:StateReason,Depuis:StateUpdatedTimestamp}"

**2. Identifier le message en DLQ**

    aws sqs receive-message \
      --queue-url "https://sqs.eu-west-3.amazonaws.com/792390865255/tp10-dlq" \
      --max-number-of-messages 10 \
      --profile training

→ Relever `item_id`, `user_id`, `product` pour identifier la commande impactée.

**3. Analyser les logs du consumer**

    aws logs tail /aws/lambda/tp10-consumer --since 30m --profile training

→ Chercher : exception Python, timeout DynamoDB, erreur de credentials.

**4. Corriger la cause racine**

| Cause | Action |
|---|---|
| Bug code | Déployer un fix, rejouer le message |
| Timeout DynamoDB | Augmenter timeout Lambda, vérifier capacité table |
| Erreur IAM | Vérifier policy `tp10-consumer-role` |
| FORCE_ERROR actif | `update-function-configuration FORCE_ERROR=false` |

**5. Rejouer le message depuis la DLQ**

    aws sqs send-message \
      --queue-url "https://sqs.eu-west-3.amazonaws.com/792390865255/tp10-queue" \
      --message-body '<body du message DLQ>' \
      --profile training

**6. Valider la résolution**

    aws cloudwatch describe-alarms \
      --alarm-names "tp11-alarm-dlq-not-empty" \
      --profile training \
      --query "MetricAlarms[0].StateValue"

→ Résultat attendu : `"OK"`

---

## Structure du projet

    tp11/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.example
