import os
import logging
from flask import Flask, jsonify, request
import boto3
from botocore.exceptions import ClientError

app = Flask(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TABLE_NAME = os.environ.get("DYNAMODB_TABLE", "exercise24-customers")
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")

try:
    dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
    table = dynamodb.Table(TABLE_NAME)
    logger.info(f"Initialized DynamoDB connection for table '{TABLE_NAME}' in region '{AWS_REGION}'.")
except Exception as e:
    logger.error(f"Error initializing DynamoDB connection: {str(e)}")
    table = None

@app.route("/healthz", methods=["GET"])
def healthz():
    return "OK", 200

@app.route("/", methods=["GET"])
def index():
    return jsonify({
        "status": "healthy",
        "service": "customer-api",
        "target_table": TABLE_NAME,
        "region": AWS_REGION
    })

@app.route("/customer", methods=["POST"])
def create_customer():
    if not table:
        return jsonify({"error": "DynamoDB table connection not initialized"}), 500
        
    data = request.get_json()
    if not data or "id" not in data or "name" not in data:
        return jsonify({"error": "Missing required fields: 'id' and 'name' are required"}), 400
        
    customer_id = str(data["id"])
    name = str(data["name"])
    email = data.get("email", "")
    phone = data.get("phone", "")
    
    try:
        table.put_item(
            Item={
                "id": customer_id,
                "name": name,
                "email": email,
                "phone": phone
            }
        )
        logger.info(f"Successfully created customer {customer_id}")
        return jsonify({
            "message": "Customer created successfully",
            "customer": {
                "id": customer_id,
                "name": name,
                "email": email,
                "phone": phone
            }
        }), 201
    except ClientError as e:
        logger.error(f"boto3 ClientError in put_item: {e.response['Error']['Message']}")
        return jsonify({"error": e.response["Error"]["Message"]}), 500
    except Exception as e:
        logger.error(f"Unexpected error in create_customer: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/customer/<id>", methods=["GET"])
def get_customer(id):
    if not table:
        return jsonify({"error": "DynamoDB table connection not initialized"}), 500
        
    try:
        response = table.get_item(Key={"id": str(id)})
        item = response.get("Item")
        if not item:
            return jsonify({"error": f"Customer with ID {id} not found"}), 404
            
        logger.info(f"Successfully retrieved customer {id}")
        return jsonify(item), 200
    except ClientError as e:
        logger.error(f"boto3 ClientError in get_item: {e.response['Error']['Message']}")
        return jsonify({"error": e.response["Error"]["Message"]}), 500
    except Exception as e:
        logger.error(f"Unexpected error in get_customer: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/customer/<id>", methods=["PUT"])
def update_customer(id):
    if not table:
        return jsonify({"error": "DynamoDB table connection not initialized"}), 500
        
    data = request.get_json()
    if not data:
        return jsonify({"error": "No update fields provided"}), 400
        
    update_expression_parts = []
    expression_attribute_values = {}
    expression_attribute_names = {}
    
    for field in ["name", "email", "phone"]:
        if field in data:
            placeholder_name = f"#field_{field}"
            placeholder_val = f":val_{field}"
            update_expression_parts.append(f"{placeholder_name} = {placeholder_val}")
            expression_attribute_names[placeholder_name] = field
            expression_attribute_values[placeholder_val] = str(data[field])
            
    if not update_expression_parts:
        return jsonify({"error": "No valid fields provided for update. Supported fields: 'name', 'email', 'phone'"}), 400
        
    update_expression = "SET " + ", ".join(update_expression_parts)
    
    try:
        response = table.update_item(
            Key={"id": str(id)},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=expression_attribute_names,
            ExpressionAttributeValues=expression_attribute_values,
            ReturnValues="ALL_NEW"
        )
        logger.info(f"Successfully updated customer {id}")
        return jsonify({
            "message": "Customer updated successfully",
            "customer": response.get("Attributes")
        }), 200
    except ClientError as e:
        logger.error(f"boto3 ClientError in update_item: {e.response['Error']['Message']}")
        return jsonify({"error": e.response["Error"]["Message"]}), 500
    except Exception as e:
        logger.error(f"Unexpected error in update_customer: {str(e)}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
