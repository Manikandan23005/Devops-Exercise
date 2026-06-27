
resource "aws_dynamodb_table" "customers" {
  name         = "exercise24-customers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Environment = "production"
    Exercise    = "24"
  }
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB Table"
  value       = aws_dynamodb_table.customers.arn
}
