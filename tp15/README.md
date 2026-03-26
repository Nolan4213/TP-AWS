TP15 - FinOps et résilience : budgets, tags, continuité, runbook PRA
Objectif : mettre en place une gouvernance coûts minimale, vérifier l'usage des tags, simuler un incident et formaliser un runbook PRA pour les TPs précédents (TP10–TP14).

1. Budget mensuel AWS
Un budget mensuel permet de suivre le coût global du compte de TP et de recevoir des alertes avant dérive.
Budget créé

Nom : TP-AWS-monthly
Type : COST
Période : MONTHLY
Limite : 20 EUR (valeur indicative)
Périmètre : compte 792390865255

Commande utilisée
powershellaws budgets create-budget `
  --account-id 792390865255 `
  --profile training `
  --budget '{
    "BudgetName": "TP-AWS-monthly",
    "BudgetType": "COST",
    "BudgetLimit": { "Amount": "20", "Unit": "EUR" },
    "TimeUnit": "MONTHLY",
    "CostFilters": {},
    "CostTypes": {
      "IncludeTax": true,
      "IncludeSubscription": true,
      "UseBlended": false,
      "IncludeRefund": false,
      "IncludeCredit": false,
      "IncludeUpfront": true,
      "IncludeRecurring": true,
      "IncludeOtherSubscription": true,
      "IncludeSupport": true,
      "IncludeDiscount": true,
      "UseAmortized": false
    }
  }'
Les notifications (vers e-mail ou SNS) peuvent être ajoutées depuis la console AWS Budgets si nécessaire.

2. Vérification des tags
Les tags standard du module sont : Project, Owner, Env, CostCenter. Ils doivent être présents sur les ressources principales des TPs (ALB, ECS, Lambda, DynamoDB, S3…).
Exemple de contrôle via Resource Groups Tagging
powershellaws resourcegroupstaggingapi get-resources `
  --tag-filters Key=Project,Values=TP14 `
  --profile training
Exemple de contrôle sur un ALB
Récupération de l'ARN :
powershellaws elbv2 describe-load-balancers `
  --names tp14-alb `
  --profile training `
  --query "LoadBalancers.LoadBalancerArn" `
  --output text
Puis vérification des tags :
powershellaws elbv2 describe-tags `
  --resource-arns <alb-arn> `
  --profile training
La même approche peut être appliquée à :

ECS service tp14-service
ECR repo tp14-nginx
Lambdas tp10-validator, tp10-consumer
DynamoDB tp8-orders


3. Simulation d'incident
Deux scénarios illustrent la continuité de service et la capacité de restauration.
3.1 Incident pipeline asynchrone (TP10)
Contexte : API Gateway + SQS + Lambda consumer + DynamoDB, avec DLQ supervisée par TP11.
Simulation : réactiver FORCE_ERROR=true sur tp10-consumer pour forcer l'échec du traitement et l'envoi en DLQ.
Activation de l'erreur :
powershellaws lambda update-function-configuration `
  --function-name tp10-consumer `
  --environment "Variables={DYNAMODB_TABLE=tp8-orders,FORCE_ERROR=true,SECRET_ARN=<secret-arn-si-utilisé>}" `
  --profile training
Envoi d'une requête :
powershellInvoke-RestMethod -Method POST `
  -Uri "https://<api-id>.execute-api.eu-west-3.amazonaws.com/items" `
  -ContentType "application/json" `
  -Body '{"user_id": "USER#PRA", "product": "PRA-Test", "amount": 1}'
Vérification DLQ :
powershellaws sqs receive-message `
  --queue-url "<dlq-url>" `
  --max-number-of-messages 5 `
  --profile training
Restauration du flux nominal :
powershellaws lambda update-function-configuration `
  --function-name tp10-consumer `
  --environment "Variables={DYNAMODB_TABLE=tp8-orders,FORCE_ERROR=false,SECRET_ARN=<secret-arn-si-utilisé>}" `
  --profile training
Rejeu du message (optionnel) : renvoyer le Body du message DLQ dans la queue principale.

3.2 Incident service Fargate (TP14)
Contexte : NGINX sur ECS Fargate derrière un ALB.
Simulation : mettre desired_count = 0 pour simuler une perte de capacité compute.
Mise à 0 :
powershellaws ecs update-service `
  --cluster tp14-cluster `
  --service tp14-service `
  --desired-count 0 `
  --region eu-west-3 `
  --profile training
À ce stade, l'ALB répond en erreur (pas de cible healthy).
Restauration :
powershellaws ecs update-service `
  --cluster tp14-cluster `
  --service tp14-service `
  --desired-count 1 `
  --region eu-west-3 `
  --profile training

4. Runbook PRA
4.1 Contexte
Périmètre du PRA :

Pipeline asynchrone de commandes : API Gateway → Lambda validator → SQS → Lambda consumer → DynamoDB (TP10)
Observabilité : dashboard CloudWatch, alarmes DLQ et erreurs Lambda (TP11)
Secrets et chiffrement : KMS + Secrets Manager pour les credentials (TP12)
Service conteneurisé exposé via ALB : NGINX sur Fargate (TP14)

Objectifs :

RTO (Recovery Time Objective) cible : 15 minutes
RPO (Recovery Point Objective) cible : 5 minutes de données maximum perdues


4.2 Scénario A – Messages bloqués en DLQ (TP10)
Symptômes :

Alarme tp11-alarm-dlq-not-empty en état ALARM
Messages présents dans la DLQ tp10-dlq
Certains utilisateurs ne voient pas leurs commandes traitées

Étapes de triage :
Confirmer l'alarme :
powershellaws cloudwatch describe-alarms `
  --alarm-names "tp11-alarm-dlq-not-empty" `
  --profile training `
  --query "MetricAlarms.{Etat:StateValue,Raison:StateReason}"
Lire un message DLQ :
powershellaws sqs receive-message `
  --queue-url "<dlq-url>" `
  --max-number-of-messages 1 `
  --profile training
Identifier item_id, user_id, product, amount.
Analyser les logs du consumer :
powershellaws logs tail /aws/lambda/tp10-consumer --since 15m --profile training
Vérifier :

Erreur applicative (FORCE_ERROR, bug métier)
Erreur IAM (permissions DynamoDB, Secrets, KMS)
Timeout, throttling

Actions de remédiation :
Corriger la cause (code, configuration ou IAM), puis vérifier que FORCE_ERROR est bien à false.
Rejeu optionnel des messages DLQ vers la queue principale :
powershellaws sqs send-message `
  --queue-url "<queue-url-principale>" `
  --message-body '<body du message DLQ>' `
  --profile training
Validation de la reprise :

Alarme DLQ repasse en OK
Les nouvelles commandes sont traitées (status = PROCESSED en DynamoDB)
Les commandes rejouées réapparaissent dans DynamoDB


4.3 Scénario B – Service Fargate indisponible (TP14)
Symptômes :

Le site NGINX rend des erreurs (ALB 5xx ou connexion refusée)
Aucune tâche Fargate en état RUNNING dans le service tp14-service

Étapes de triage :
Vérifier l'état du service ECS :
powershellaws ecs describe-services `
  --cluster tp14-cluster `
  --services tp14-service `
  --region eu-west-3 `
  --profile training `
  --query "services.{Desired:desiredCount,Running:runningCount,Status:status}"
Vérifier les événements ECS et les tâches en échec (ex : image non trouvée, IAM, réseau).
Consulter les logs CloudWatch des conteneurs :

Groupe de logs : /ecs/tp14
Streams : préfixés par nginx/

Actions de remédiation :
Remonter le service :
powershellaws ecs update-service `
  --cluster tp14-cluster `
  --service tp14-service `
  --desired-count 1 `
  --region eu-west-3 `
  --profile training
Forcer un nouveau déploiement :
powershellaws ecs update-service `
  --cluster tp14-cluster `
  --service tp14-service `
  --force-new-deployment `
  --region eu-west-3 `
  --profile training
Validation :

Une tâche au moins en RUNNING
Target group tp14-tg : toutes les cibles en healthy
L'URL ALB affiche la page NGINX TP14


5. Résumé des bonnes pratiques appliquées

Budgets configurés pour surveiller le coût global du compte de TP
Tags Project, Owner, Env, CostCenter systématisés sur les ressources critiques
Scénarios d'incident testés sur le pipeline asynchrone et le service Fargate
Runbook PRA documenté pour accélérer le triage et la restauration