import boto3
import json
import logging
import os
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["SQS_QUEUE_URL"]

def lambda_handler(event, context):
    request_id = context.aws_request_id

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        logger.error(json.dumps({
            "request_id": request_id,
            "status": "REJECTED",
            "reason": "Payload JSON invalide"
        }))
        return {"statusCode": 400, "body": json.dumps({"error": "Payload JSON invalide"})}

    # Validation des champs obligatoires
    required = ["user_id", "product", "amount"]
    missing = [f for f in required if f not in body]
    if missing:
        logger.error(json.dumps({
            "request_id": request_id,
            "status": "REJECTED",
            "reason": f"Champs manquants : {missing}"
        }))
        return {"statusCode": 400, "body": json.dumps({"error": f"Champs manquants : {missing}"})}

    # Enrichissement du message
    message = {
        "item_id": str(uuid.uuid4()),
        "user_id": body["user_id"],
        "product": body["product"],
        "amount": body["amount"],
        "request_id": request_id,
        "status": "PENDING"
    }

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(message)
    )

    logger.info(json.dumps({
        "request_id": request_id,
        "status": "QUEUED",
        "item_id": message["item_id"]
    }))

    return {"statusCode": 200, "body": json.dumps({"item_id": message["item_id"], "status": "QUEUED"})}
