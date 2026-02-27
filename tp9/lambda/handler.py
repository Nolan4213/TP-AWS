import boto3
import json
import logging
import os
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
        key = unquote_plus(record["s3"]["object"]["key"])
        size = record["s3"]["object"]["size"]

        logger.info(json.dumps({
            "request_id": request_id,
            "status": "RECEIVED",
            "bucket": bucket,
            "key": key,
            "size": size
        }))

        # Validation extension
        ext = os.path.splitext(key)[1].lower()
        if ext not in ALLOWED_EXTENSIONS:
            logger.error(json.dumps({
                "request_id": request_id,
                "status": "REJECTED",
                "reason": f"Extension non autorisée : {ext}",
                "key": key
            }))
            continue

        # Validation taille
        if size > MAX_SIZE_BYTES:
            logger.error(json.dumps({
                "request_id": request_id,
                "status": "REJECTED",
                "reason": f"Fichier trop volumineux : {size} bytes (max 5MB)",
                "key": key
            }))
            continue

        # Cas nominal : écriture résumé dans output/
        filename = os.path.basename(key)
        output_key = f"output/{filename}.json"
        summary = {
            "request_id": request_id,
            "status": "ACCEPTED",
            "source_key": key,
            "extension": ext,
            "size_bytes": size
        }

        s3.put_object(
            Bucket=bucket,
            Key=output_key,
            Body=json.dumps(summary),
            ContentType="application/json"
        )

        logger.info(json.dumps({
            "request_id": request_id,
            "status": "ACCEPTED",
            "output_key": output_key,
            "size_bytes": size
        }))

    return {"statusCode": 200}
