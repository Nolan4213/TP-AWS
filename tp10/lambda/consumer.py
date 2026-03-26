import boto3
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE"]
FORCE_ERROR = os.environ.get("FORCE_ERROR", "false")

def lambda_handler(event, context):
    table = dynamodb.Table(TABLE_NAME)

    for record in event["Records"]:
        body = json.loads(record["body"])
        item_id = body.get("item_id", "unknown")

        logger.info(json.dumps({
            "request_id": context.aws_request_id,
            "status": "PROCESSING",
            "item_id": item_id
        }))

        # Mode erreur forcée pour tester la DLQ
        if FORCE_ERROR == "true":
            logger.error(json.dumps({
                "request_id": context.aws_request_id,
                "status": "ERROR",
                "item_id": item_id,
                "reason": "Erreur forcée pour test DLQ"
            }))
            raise Exception("Erreur forcée pour test DLQ")

        # Écriture dans DynamoDB
        table.put_item(Item={
            "PK": body['user_id'],
            "SK": f"ORDER#{item_id}",
            "item_id": item_id,
            "product": body["product"],
            "amount": int(body["amount"]),
            "status": "PROCESSED",
            "request_id": body["request_id"]
        })

        logger.info(json.dumps({
            "request_id": context.aws_request_id,
            "status": "PROCESSED",
            "item_id": item_id
        }))
