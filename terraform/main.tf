data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../lambda/fetch_crypto_price/"
  output_path = "lambda_function.zip"
}

module "label_lambda" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git?ref=main"
  namespace   = var.namespace
  environment = var.environment
  stage       = var.stage
  name        = "lambda_fetch_crypto_price"
  label_order = ["namespace", "stage", "environment", "name", "attributes"]
  tags = {
    "Terraform" = "true"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${module.label_lambda.id}_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "lambda_function" {
  function_name = module.label_lambda.name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.9"
  filename      = data.archive_file.lambda_zip.output_path

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${module.label_lambda.name}_api"
  description = "API Gateway for Lambda function ${module.label_lambda.name}"
}

resource "aws_api_gateway_resource" "lambda_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "fetch"
}

resource "aws_api_gateway_method" "lambda_method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.lambda_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.lambda_resource.id
  http_method             = aws_api_gateway_method.lambda_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.lambda_function.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = var.stage
}

output "api_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda_function.arn
}
