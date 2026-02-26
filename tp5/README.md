# TP5 — ALB + ASG multi-AZ via Terraform

> **Objectif** : Déployer une architecture haute disponibilité avec un Application Load Balancer
> et un Auto Scaling Group répartis sur 2 zones de disponibilité, administrée via Terraform.

---

## Architecture

```
         Internet
             │
         HTTP :80
             │
             ▼
 ┌───────────────────────┐
 │      tp5-alb (ALB)    │  ← Subnets publics (eu-west-3a / eu-west-3b)
 │  SG: 0.0.0.0/0 → 80  │
 └──────────┬────────────┘
            │ HTTP :80 (ALB → instances uniquement)
   ┌─────────┴─────────┐
   ▼                   ▼
┌────────┐         ┌────────┐
│  EC2   │         │  EC2   │  ← Subnets privés
│  3a    │         │  3b    │     nginx + IMDSv2
└────────┘         └────────┘
   Auto Scaling Group (min:2 / max:4)
```

---

## Ressources Terraform

| Ressource | Nom | Description |
|---|---|---|
| ALB | `tp5-alb` | Load balancer public internet-facing |
| Target Group | `tp5-tg` | Health check HTTP sur `/` |
| ASG | `tp5-asg` | 2 à 4 instances multi-AZ |
| Launch Template | `tp5-lt` | Amazon Linux 2023 + nginx + IMDSv2 |
| Security Group | `tp5-alb-sg` | HTTP 80 ouvert depuis Internet |
| Security Group | `tp5-app-sg` | HTTP 80 depuis ALB uniquement |
| NAT Gateway | `tp5-nat` | Temporaire — supprimé après bootstrap nginx |

---

## Prérequis

- AWS CLI configuré avec le profil `training`
- VPC, subnets et Security Groups du **TP3** existants
- IAM Instance Profile `EC2SSMProfile` créé en **TP4**
- Terraform >= 1.0

---

## Déploiement

```bash
# 1. Copier et remplir les variables
cp terraform.tfvars.example terraform.tfvars

# 2. Initialiser le provider AWS
terraform init

# 3. Vérifier ce qui va être créé
terraform plan

# 4. Déployer l'infrastructure
terraform apply
```

## Teardown

```bash
terraform destroy
```

---

## Sécurité appliquée

- **IMDSv2 forcé** sur toutes les instances (`HttpTokens = required`) — protection SSRF
- **Pas de SSH exposé** — administration via SSM Session Manager uniquement
- **Principe du moindre privilège** sur les Security Groups :
  - Internet → ALB uniquement (port 80)
  - ALB → instances uniquement (port 80)
  - Instances → pas accessibles directement depuis Internet

---

## Preuves de validation

### 1. Instances healthy dans le Target Group

```
------------------------------------
|       DescribeTargetHealth       |
+----------------------+-----------+
|          ID          |   State   |
+----------------------+-----------+
|  i-02f3d48f2f3b31207 |  healthy  |
|  i-0f260ef5c7e3c661a |  healthy  |
+----------------------+-----------+
```

---

### 2. Réponse HTTP 200 depuis l'ALB

```
StatusCode        : 200
StatusDescription : OK
Content           : <h1>TP5 - ip-10-0-10-242.eu-west-3.compute.internal
                    - Thu Feb 26 09:08:05 UTC 2026</h1>
```

> URL : http://tp5-alb-42688838.eu-west-3.elb.amazonaws.com

---

### 3. Simulation de panne — auto-healing ASG

Instance `i-02f3d48f2f3b31207` terminée manuellement pour simuler une panne :

```json
{
  "TerminatingInstances": [{
    "InstanceId": "i-02f3d48f2f3b31207",
    "CurrentState":  { "Name": "shutting-down" },
    "PreviousState": { "Name": "running" }
  }]
}
```

**Immédiatement** — l'ASG détecte la panne et lance un remplacement automatique :

```
+------------+-----------------------+---------------+
|   Health   |          ID           |     State     |
+------------+-----------------------+---------------+
|  Unhealthy |  i-02f3d48f2f3b31207  |  Terminating  |
|  Healthy   |  i-0f260ef5c7e3c661a  |  InService    |
|  Healthy   |  i-0f8d453d20584ff84  |  Pending      |  ← nouvelle instance
+------------+-----------------------+---------------+
```

**~2 minutes plus tard** — disponibilité totalement restaurée :

```
+------------+-----------------------+---------------+
|   Health   |          ID           |     State     |
+------------+-----------------------+---------------+
|  Healthy   |  i-0f260ef5c7e3c661a  |  InService    |
|  Healthy   |  i-0f8d453d20584ff84  |  InService    |  ← remplacée automatiquement
+------------+-----------------------+---------------+
```

> L'ASG maintient toujours **2 instances minimum** sans aucune intervention humaine.
