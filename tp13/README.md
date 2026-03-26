TP13 - CloudFormation : socle réseau VPC reproductible
Objectif : déployer un socle VPC complet via CloudFormation et maîtriser le cycle create / update (change set) / delete.
​

Architecture déployée
VPC /16 avec DNS support et DNS hostnames activés.
​

Deux subnets publics (AZ a et b), sans attribution automatique d’IP publique.

Deux subnets privés (AZ a et b).

Une Internet Gateway attachée au VPC.

Une route table publique (route 0.0.0.0/0 vers l’IGW) associée aux subnets publics.

Une route table privée associée aux subnets privés.

Toutes les ressources principales sont taggées : Project, Owner, Env, CostCenter.
​

Fichiers du TP
tp13/

template.yaml (VPC, subnets, IGW, routes, tags, outputs)

parameters.json (paramètres de déploiement)

Paramètres principaux
Contenu de parameters.json :

ProjectName = TP13

Owner = tp-session

Env = training

CostCenter = formation-aws

VpcCidr = 10.13.0.0/16

PublicSubnet1Cidr = 10.13.1.0/24

PublicSubnet2Cidr = 10.13.2.0/24

PrivateSubnet1Cidr = 10.13.3.0/24

PrivateSubnet2Cidr = 10.13.4.0/24

Déploiement de la stack
Commande utilisée :

aws cloudformation deploy
--template-file template.yaml
--stack-name tp13-vpc
--parameter-overrides file://parameters.json
--profile training

Outputs de la stack
Commande :

aws cloudformation describe-stacks
--stack-name tp13-vpc
--profile training
--query "Stacks.Outputs[*].{Cle:OutputKey,Valeur:OutputValue}"

Résultat :

InternetGatewayId = igw-01592da4346236ca1

VpcId = vpc-0b556e6a4fc6b0520

PublicSubnet1Id = subnet-088ea40a55fec9bc0

PublicSubnet2Id = subnet-091cb6f7aca3bec07

PrivateRouteTableId = rtb-09d781d1dea82422f

PrivateSubnet2Id = subnet-03e19e3d1a0f4f31e

PrivateSubnet1Id = subnet-077f67d2ad619e327

PublicRouteTableId = rtb-0222b4abaf4c4c80c

Change set (update contrôlé)
Création d’un change set après modification mineure des paramètres :

aws cloudformation create-change-set
--stack-name tp13-vpc
--change-set-name tp13-vpc-change1
--template-body file://template.yaml
--parameters file://parameters.json
--profile training

Visualisation :

aws cloudformation describe-change-set
--stack-name tp13-vpc
--change-set-name tp13-vpc-change1
--profile training
--query "Changes[*].{Action:ResourceChange.Action,Type:ResourceChange.ResourceType,LogicalId:ResourceChange.LogicalResourceId}"

Exécution :

aws cloudformation execute-change-set
--stack-name tp13-vpc
--change-set-name tp13-vpc-change1
--profile training

Teardown
Suppression de la stack :

aws cloudformation delete-stack
--stack-name tp13-vpc
--profile training

aws cloudformation wait stack-delete-complete
--stack-name tp13-vpc
--profile training

Vérification de la suppression du VPC :

aws ec2 describe-vpcs
--filters Name=vpc-id,Values=vpc-0b556e6a4fc6b0520
--profile training