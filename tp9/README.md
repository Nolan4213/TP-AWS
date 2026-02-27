    # TP9 - Lambda trigger S3, rôles minimaux, logs et gestion d'erreurs

> Objectif : Traiter un événement S3, valider un objet et produire une sortie.
> Maîtriser les permissions et prouver une exécution observable.

> 📁 Les captures d'écran des preuves de déploiement sont disponibles
> dans le dossier [docs/](docs/).

---

## Architecture

    S3 bucket (training-nolan)
    ├── input/          ← trigger Lambda sur upload
    └── output/         ← résumé JSON écrit par Lambda (cas nominal uniquement)

    Lambda (Python 3.12) — tp9-s3-validator
    ├── Valide extension (.jpg, .jpeg, .png, .pdf uniquement)
    ├── Valide taille max (< 5 MB)
    ├── Cas nominal  → écrit résumé JSON dans output/
    └── Cas erreur   → log CloudWatch REJECTED + aucune écriture

    CloudWatch Logs
    └── /aws/lambda/tp9-s3-validator

---

## Rôle IAM minimal

Aucun `s3:*` — permissions ciblées par préfixe :

| Permission | Ressource ciblée |
|---|---|
| `s3:GetObject` | `arn:aws:s3:::training-nolan/input/*` |
| `s3:PutObject` | `arn:aws:s3:::training-nolan/output/*` |
| `logs:CreateLogGroup` | `/aws/lambda/tp9-s3-validator` |
| `logs:CreateLogStream` | `/aws/lambda/tp9-s3-validator` |
| `logs:PutLogEvents` | `/aws/lambda/tp9-s3-validator` |

---

## Infrastructure Terraform

### Ressources déployées

- Rôle IAM `tp9-lambda-role` avec policy minimale
- Lambda `tp9-s3-validator` (Python 3.12, 128 MB, timeout 30s)
- CloudWatch Log Group `/aws/lambda/tp9-s3-validator` (retention 7 jours)
- Permission `lambda:InvokeFunction` pour S3
- Notification S3 trigger sur préfixe `input/`

### Commandes de déploiement

    terraform init
    terraform plan
    terraform apply

### Outputs

    lambda_name = "tp9-s3-validator"
    lambda_arn  = "arn:aws:lambda:eu-west-3:792390865255:function:tp9-s3-validator"
    log_group   = "/aws/lambda/tp9-s3-validator"

---

## Code Lambda

    import boto3, json, logging, os
    from urllib.parse import unquote_plus

    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    s3 = boto3.client("s3")

    ALLOWED_EXTENSIONS = [".jpg", ".jpeg", ".png", ".pdf"]
    MAX_SIZE_BYTES = 5 * 1024 * 1024  # 5 MB

    def lambda_handler(event, context):
        request_id = context.aws_request_id
        for record in event["Records"]:
            bucket = record["s3"]["bucket"]["name"]
            key    = unquote_plus(record["s3"]["object"]["key"])
            size   = record["s3"]["object"]["size"]

            logger.info(json.dumps({"request_id": request_id,
                "status": "RECEIVED", "bucket": bucket,
                "key": key, "size": size}))

            ext = os.path.splitext(key)[1].lower()
            if ext not in ALLOWED_EXTENSIONS:
                logger.error(json.dumps({"request_id": request_id,
                    "status": "REJECTED",
                    "reason": f"Extension non autorisée : {ext}",
                    "key": key}))
                continue

            if size > MAX_SIZE_BYTES:
                logger.error(json.dumps({"request_id": request_id,
                    "status": "REJECTED",
                    "reason": f"Fichier trop volumineux : {size} bytes",
                    "key": key}))
                continue

            output_key = f"output/{os.path.basename(key)}.json"
            summary = {"request_id": request_id, "status": "ACCEPTED",
                       "source_key": key, "extension": ext, "size_bytes": size}
            s3.put_object(Bucket=bucket, Key=output_key,
                          Body=json.dumps(summary),
                          ContentType="application/json")
            logger.info(json.dumps({"request_id": request_id,
                "status": "ACCEPTED", "output_key": output_key,
                "size_bytes": size}))
        return {"statusCode": 200}

---

## Tests de validation

### Commandes exécutées

    aws s3 cp test-valid.jpg s3://training-nolan/input/test-valid.jpg --profile training
    aws s3 cp test-invalid.exe s3://training-nolan/input/test-invalid.exe --profile training
    aws s3 ls s3://training-nolan/output/ --profile training

Résultat output/ :

    2026-02-27 12:31:48   153   test-valid.jpg.json

> ✅ Seul le fichier valide a produit une sortie dans output/

---

## Logs CloudWatch

    aws logs tail /aws/lambda/tp9-s3-validator --since 30m --profile training

### Cas nominal — test-valid.jpg (ACCEPTED)

    INIT_START Runtime Version: python:3.12.mainlinev2.v3

    START RequestId: f945b9ae-1bad-48bc-984f-43d947ee1d7a Version: $LATEST

    [INFO] {"request_id": "f945b9ae-1bad-48bc-984f-43d947ee1d7a",
            "status": "RECEIVED", "bucket": "training-nolan",
            "key": "input/test-valid.jpg", "size": 26}

    [INFO] {"request_id": "f945b9ae-1bad-48bc-984f-43d947ee1d7a",
            "status": "ACCEPTED",
            "output_key": "output/test-valid.jpg.json", "size_bytes": 26}

    END RequestId: f945b9ae-1bad-48bc-984f-43d947ee1d7a
    REPORT RequestId: f945b9ae-1bad-48bc-984f-43d947ee1d7a
           Duration: 305.61 ms   Billed Duration: 777 ms
           Memory Size: 128 MB   Max Memory Used: 92 MB
           Init Duration: 470.58 ms

### Cas erreur — test-invalid.exe (REJECTED)

    START RequestId: a28042c9-74af-42f0-aaf7-062c47c50466 Version: $LATEST

    [INFO]  {"request_id": "a28042c9-74af-42f0-aaf7-062c47c50466",
             "status": "RECEIVED", "bucket": "training-nolan",
             "key": "input/test-invalid.exe", "size": 38}

    [ERROR] {"request_id": "a28042c9-74af-42f0-aaf7-062c47c50466",
             "status": "REJECTED",
             "reason": "Extension non autorisée : .exe",
             "key": "input/test-invalid.exe"}

    END RequestId: a28042c9-74af-42f0-aaf7-062c47c50466
    REPORT RequestId: a28042c9-74af-42f0-aaf7-062c47c50466
           Duration: 1.69 ms   Billed Duration: 2 ms
           Memory Size: 128 MB   Max Memory Used: 92 MB

> ✅ request_id présent dans chaque log
> ✅ Cas nominal : ACCEPTED + écriture output/
> ✅ Cas erreur : REJECTED loggé + aucune écriture output/

---

## Teardown

Objets de test supprimés après validation :

    aws s3 rm s3://training-nolan/input/test-valid.jpg --profile training
    aws s3 rm s3://training-nolan/input/test-invalid.exe --profile training
    aws s3 rm s3://training-nolan/output/test-va
