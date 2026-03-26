import json
import os
import boto3
import logging
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
secrets  = boto3.client("secretsmanager")

def get_secret():
    secret_arn = os.environ.get("SECRET_ARN")
    if not secret_arn:
        return None
    response = secrets.get_secret_value(SecretId=secret_arn)
    return json.loads(response["SecretString"])

def lambda_handler(event, context):
    request_id = context.aws_request_id
    table_name = os.environ.get("DYNAMODB_TABLE", "tp8-orders")
    force_error = os.environ.get("FORCE_ERROR", "false").lower() == "true"
    table = dynamodb.Table(table_name)

    # Lecture du secret au runtime
    secret = get_secret()
    if secret:
        logger.info(json.dumps({
            "request_id": request_id,
            "status":     "SECRET_LOADED",
            "db_host":    secret.get("host"),
            "db_user":    secret.get("username"),
            # password jamais loggé
        }))

    for record in event.get("Records", []):
        body = json.loads(record["body"])
        item_id = body.get("item_id", str(uuid.uuid4()))

        logger.info(json.dumps({
            "request_id": request_id,
            "status":     "PROCESSING",
            "item_id":    item_id,
        }))

        if force_error:
            raise Exception(f"FORCE_ERROR activé — item {item_id} rejeté volontairement")

        table.put_item(Item={
            "PK":         body["user_id"],
            "SK":         f"ORDER#{item_id}",
            "item_id":    item_id,
            "product":    body.get("product"),
            "amount":     body.get("amount"),
            "status":     "PROCESSED",
            "request_id": request_id,
        })

        logger.info(json.dumps({
            "request_id": request_id,
            "status":     "PROCESSED",
            "item_id":    item_id,
        }))
