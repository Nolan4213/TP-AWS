
# TP14 - ECS Fargate, ECR, ALB, logs CloudWatch

**Objectif :** déployer un service conteneurisé NGINX sur ECS Fargate, exposé via un ALB public, avec logs envoyés vers CloudWatch Logs.

---

## Architecture déployée

- Un repository ECR privé : `tp14-nginx`
- Un cluster ECS Fargate : `tp14-cluster`
- Une task definition Fargate : conteneur NGINX, 0.25 vCPU, 0.5 Go, logs vers CloudWatch Logs
- Un service ECS Fargate : `tp14-service`, 1 tâche, dans des subnets privés
- Un ALB public : `tp14-alb`, listener HTTP 80, target group HTTP vers le service ECS
- Deux security groups :
  - `tp14-alb-sg` : HTTP 80 autorisé depuis Internet
  - `tp14-ecs-tasks-sg` : port 80 autorisé uniquement depuis `tp14-alb-sg`

---

## Fichiers du TP

```
tp14/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
└── app/
    ├── Dockerfile
    └── index.html
```

---

## variables.tf

Variables principales :

- `aws_region` = `"eu-west-3"`
- `vpc_id` : VPC existant (TP3/TP13)
- `public_subnets` : subnets publics pour l'ALB
- `private_subnets` : subnets privés pour les tâches Fargate
- Tags standard : `project_name`, `owner`, `env`, `cost_center`

---

## terraform.tfvars.example

```hcl
aws_region   = "eu-west-3"
project_name = "tp14"
owner        = "tp-session"
env          = "training"
cost_center  = "formation-aws"

vpc_id          = "vpc-0b556e6a4fc6b0520"
public_subnets  = ["subnet-088ea40a55fec9bc0", "subnet-091cb6f7aca3bec07"]
private_subnets = ["subnet-077f67d2ad619e327", "subnet-03e19e3d1a0f4f31e"]
```

---

## Application conteneurisée

### app/Dockerfile

```dockerfile
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### app/index.html

```html
<!DOCTYPE html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <title>TP14 - ECS Fargate</title>
  </head>
  <body>
    <h1>TP14 - ECS Fargate + ALB</h1>
    <p>Container NGINX déployé sur Fargate derrière un ALB.</p>
  </body>
</html>
```

---

## Déploiement de l'infrastructure

Dans `tp14/` :

```bash
cp terraform.tfvars.example terraform.tfvars   # puis édition des IDs
terraform init
terraform apply
```

Outputs obtenus :

```
alb_dns_name        = "tp14-alb-584344940.eu-west-3.elb.amazonaws.com"
ecr_repository_url  = "792390865255.dkr.ecr.eu-west-3.amazonaws.com/tp14-nginx"
```

L'ALB est accessible en HTTP sur :

```
http://tp14-alb-584344940.eu-west-3.elb.amazonaws.com
```

La page **TP14 - ECS Fargate + ALB** s'affiche correctement.

---

## Ressources Terraform principales

### ECR

```hcl
resource "aws_ecr_repository" "nginx" {
  name                 = "${var.project_name}-nginx"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}
```

### ECS Cluster

```hcl
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
  tags = local.tags
}
```

### ALB + Security Groups

```hcl
resource "aws_security_group" "alb" { ... }
resource "aws_security_group" "ecs_tasks" { ... }

resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets
}

resource "aws_lb_target_group" "this" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path    = "/"
    matcher = "200"
  }
}
```

### Task Definition Fargate

```hcl
resource "aws_ecs_task_definition" "nginx" {
  family                   = "${var.project_name}-nginx"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "${aws_ecr_repository.nginx.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nginx"
        }
      }
    }
  ])
}
```

### Service ECS Fargate

```hcl
resource "aws_ecs_service" "nginx" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.nginx.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]
}
```