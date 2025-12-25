# API Gateway Infrastructure (REST API)

AWS REST API Gateway infrastructure with Lambda JWT authorizer following the ConnectX pattern.

## Architecture

**ConnectX Pattern**: Centralized REST API Gateway with Lambda authorizer for all microservices.

### Key Features

- **REST API**: Full-featured API Gateway (resource policies, usage plans, API keys)
- **Free Tier**: 1M API calls/month free for 12 months
- **Lambda Authorizer**: JWT validation with Cognito (REQUEST type)
- **Health Check**: `/health` endpoint for monitoring
- **Throttling**: Configurable rate and burst limits
- **CloudWatch Logging**: Request/response logging
- **Custom Domain**: Optional Route53 integration
- **Multi-Tenant**: Tenant validation via JWT claims

## Cost Breakdown

### REST API Gateway

#### Free Tier (12 months)
- **1 million API calls/month**: FREE
- **Duration**: 12 months from account creation

#### After Free Tier
- First 333 million requests: $3.50 per million
- Next 667 million requests: $2.80 per million
- Next 19 billion requests: $2.38 per million
- Over 20 billion requests: $1.51 per million

### Data Transfer
- First 10TB out: $0.09/GB
- Next 40TB out: $0.085/GB
- Over 150TB out: $0.05/GB

### Example Monthly Cost (after free tier)
- 1M requests: $3.50
- 10M requests: $35.00
- 100M requests: $350.00
- 1B requests: $2,800.00

**Note**: REST API is ~3.5x more expensive than HTTP API but includes additional enterprise features.

## Why REST API (Not HTTP API)?

User chose REST API for these enterprise features:

1. **Resource Policies**: IP whitelisting, VPC endpoints
2. **Usage Plans & API Keys**: Rate limiting per client
3. **Request/Response Transformation**: Modify payloads
4. **AWS WAF Integration**: Advanced DDoS protection
5. **Private APIs**: VPC-only access

## Environment Configurations

### Dev
```hcl
throttle_burst_limit = 5000                     # Relaxed
throttle_rate_limit = 2000                      # Relaxed
enable_authorizer = false                       # Deploy authorizer first
logging_level = "INFO"
enable_xray_tracing = false                     # Cost savings
enable_custom_domain = false                    # No domain
log_retention_days = 7
```

### PPE
```hcl
throttle_burst_limit = 2000                     # Moderate
throttle_rate_limit = 1000                      # Moderate
enable_authorizer = true
logging_level = "INFO"
enable_xray_tracing = true                      # Enable monitoring
enable_custom_domain = false                    # Optional
log_retention_days = 14
```

### Prod
```hcl
throttle_burst_limit = 1000                     # Strict
throttle_rate_limit = 500                       # Strict
enable_authorizer = true
logging_level = "INFO"
enable_xray_tracing = true                      # Full monitoring
enable_custom_domain = true                     # api.rtr.com
log_retention_days = 30
```

## Directory Structure

```
deployment/api-gateway/
├── README.md
├── deployspec.yml              # CodeBuild deployment
├── project.json                # Nx project metadata
├── environments/
│   ├── dev/
│   │   └── main.tf            # Dev configuration
│   ├── ppe/
│   │   └── main.tf            # PPE configuration
│   └── prod/
│       └── main.tf            # Prod configuration
└── resources/
    ├── provider.tf            # Provider configuration
    ├── locals.tf              # Local variables
    ├── variables.tf           # Variable declarations
    ├── api_gateway.tf         # REST API + Stage + Health check
    ├── authorizer.tf          # Lambda authorizer + IAM
    └── outputs.tf             # Output values
```

## Lambda Authorizer

### Architecture

The Lambda authorizer validates JWT tokens from Cognito (REQUEST type):

1. **Request arrives** → API Gateway extracts `Authorization` header
2. **Invoke Lambda** → Authorizer validates JWT signature
3. **Verify claims** → Check `tenantId`, expiration, issuer
4. **Cache result** → Cache IAM policy (5-10 min)
5. **Allow/Deny** → Return IAM policy to API Gateway

### Authorizer Response Format (REQUEST)

```json
{
  "principalId": "user-uuid",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "execute-api:Invoke",
      "Effect": "Allow",
      "Resource": "arn:aws:execute-api:region:account:api-id/*"
    }]
  },
  "context": {
    "userId": "user-uuid",
    "tenantId": "tenant-123",
    "email": "user@example.com"
  }
}
```

### Context Usage in Lambda

Context values are passed to backend Lambda functions:

```typescript
export const handler = async (event: APIGatewayProxyEvent) => {
  // Access authorizer context
  const userId = event.requestContext.authorizer.userId;
  const tenantId = event.requestContext.authorizer.tenantId;

  // Use tenantId for row-level isolation
  const results = await db.query(
    'SELECT * FROM jobs WHERE tenantId = $1',
    [tenantId]
  );
};
```

## Deployment

### Prerequisites

1. **Deploy general infrastructure first** (VPC, IAM, S3)
   ```bash
   cd deployment/general/environments/dev
   terraform init && terraform apply
   ```

2. **Deploy Lambda authorizer** (blocks API Gateway)
   ```bash
   cd deployment/authorizer/environments/dev
   terraform init && terraform apply
   ```

3. **Update authorizer ARN** in deployment/api-gateway/environments/dev/main.tf
   ```hcl
   authorizer_lambda_arn = "arn:aws:lambda:ap-south-1:ACCOUNT:function:rtr-dev-authorizer"
   enable_authorizer = true  # Enable after deploying authorizer
   ```

### Deploy with Terraform

```bash
# Dev environment
cd deployment/api-gateway/environments/dev
terraform init
terraform plan
terraform apply

# Get API Gateway URL
terraform output api_gateway_url
# Output: https://abc123.execute-api.ap-south-1.amazonaws.com/dev
```

### Test Health Check

```bash
# Test the /health endpoint (no auth required)
curl https://abc123.execute-api.ap-south-1.amazonaws.com/dev/health

# Expected response:
{
  "status": "healthy",
  "service": "rtr-api",
  "version": "1.0.0"
}
```

## Custom Domain Setup (Production)

### 1. Request ACM Certificate

```bash
aws acm request-certificate \
  --domain-name api.rtr.com \
  --validation-method DNS \
  --region ap-south-1
```

### 2. Validate Certificate

Add CNAME records to Route53 for validation.

### 3. Update Terraform Config

```hcl
# deployment/api-gateway/environments/prod/main.tf
enable_custom_domain = true
domain_name = "api.rtr.com"
certificate_arn = "arn:aws:acm:ap-south-1:ACCOUNT:certificate/CERT_ID"
route53_zone_id = "Z1234567890ABC"
```

### 4. Apply and Verify

```bash
terraform apply

# Test custom domain
curl https://api.rtr.com/health
```

## Adding Routes (from Apps)

### Example: Job Service Routes

In `apps/job/deploy/resources/api_gateway.tf`:

```hcl
# Data source: Reference existing API Gateway
data "aws_api_gateway_rest_api" "main" {
  name = "rtr-${var.env}-api"
}

# Reference authorizer (if needed)
data "aws_api_gateway_authorizer" "jwt" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  name        = "rtr-${var.env}-authorizer"
}

# Create resource
resource "aws_api_gateway_resource" "jobs" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "jobs"
}

# Create POST method with authorizer
resource "aws_api_gateway_method" "create_job" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt.id
}

# Integrate with Lambda
resource "aws_api_gateway_integration" "create_job" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.create_job.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.job.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_api_gateway_rest_api.main.execution_arn}/*"
}

# Trigger redeployment after adding routes
resource "aws_api_gateway_deployment" "app_deployment" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.create_job,
  ]

  lifecycle {
    create_before_destroy = true
  }
}
```

## CORS Configuration

REST API handles CORS differently than HTTP API. CORS must be configured per-resource:

```hcl
# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "jobs_options" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "jobs_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.jobs_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "jobs_options_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.jobs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_integration_response" "jobs_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.jobs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'https://rtr.com'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Tenant-ID'"
  }
}
```

## Monitoring

### CloudWatch Metrics

- **Count**: Number of API requests
- **4XXError**: Client errors (400-499)
- **5XXError**: Server errors (500-599)
- **Latency**: Request processing time
- **IntegrationLatency**: Backend processing time
- **CacheHitCount**: Authorizer cache hits
- **CacheMissCount**: Authorizer cache misses

### CloudWatch Alarms

Created automatically:
- **4XX Errors**: > threshold in 5 minutes (dev: 200, prod: 50)
- **5XX Errors**: > threshold in 5 minutes (dev: 50, prod: 10)
- **High Latency**: > threshold ms average (dev: 10s, prod: 3s)

### Access Logs

Logs are written to CloudWatch:
```
/aws/apigateway/rtr-{env}-api
```

Log format (JSON):
```json
{
  "requestId": "abc123",
  "ip": "1.2.3.4",
  "requestTime": "2024-01-01T12:00:00Z",
  "httpMethod": "POST",
  "resourcePath": "/jobs",
  "status": 200,
  "protocol": "HTTP/1.1",
  "responseLength": 1234
}
```

## Throttling

### How Throttling Works

- **Rate Limit**: Max requests per second (sustained)
- **Burst Limit**: Max concurrent requests (spike)

### Example

```
throttle_rate_limit = 500    # 500 requests/second sustained
throttle_burst_limit = 1000  # 1000 concurrent requests
```

If limits exceeded:
- Returns `429 Too Many Requests`
- Client should implement exponential backoff

### Per-Method Throttling

Can be configured per route (in app deployment):

```hcl
resource "aws_api_gateway_method_settings" "create_job" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  stage_name  = "dev"
  method_path = "jobs/POST"

  settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}
```

## Security Best Practices

1. **Always use HTTPS**: REST API enforces HTTPS
2. **Enable throttling**: Prevent abuse and DDoS
3. **Use Lambda authorizer**: Validate JWT on every request
4. **Cache authorizer results**: Balance performance vs security (5-10 min)
5. **Custom domain**: Don't expose execute-api.amazonaws.com
6. **CloudWatch alarms**: Monitor errors and latency
7. **Resource policies**: Restrict by IP or VPC (optional)
8. **Usage plans**: Rate limit per API key (optional)

## Troubleshooting

### Common Issues

1. **403 Forbidden**: Authorizer denying requests
   - Check JWT token is valid
   - Verify Cognito user pool configuration
   - Check authorizer Lambda logs in CloudWatch

2. **502 Bad Gateway**: Lambda integration error
   - Check Lambda function exists and is healthy
   - Verify Lambda permissions for API Gateway invocation
   - Check Lambda response format (must match AWS_PROXY)

3. **504 Gateway Timeout**: Lambda timeout
   - Check Lambda timeout setting (max 29s for REST API)
   - Optimize Lambda cold start
   - Add CloudWatch logs to debug

4. **CORS errors**: Preflight failing
   - Add OPTIONS method for each resource
   - Verify CORS headers match frontend origin
   - Check credentials setting matches

## Cost Optimization Tips

1. **Cache authorizer results**: Reduce Lambda invocations (5-10 min TTL)
2. **Use usage plans**: Prevent abuse and reduce costs
3. **Enable CloudWatch metrics**: Monitor and optimize
4. **Compress responses**: Reduce data transfer costs (gzip)
5. **Throttle appropriately**: Prevent runaway costs
6. **Monitor usage**: Set up billing alarms

## Deployment Order

```
1. deployment/general/      (VPC, IAM, Secrets)
2. deployment/cognito/      (User Pool)
3. deployment/authorizer/   (Lambda function)
4. deployment/api-gateway/  (REST API - this module)
5. apps/*/deploy/           (App routes and Lambdas)
```

## Resources

- [REST API Pricing](https://aws.amazon.com/api-gateway/pricing/)
- [REST API Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html)
- [Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [Request/Response Data Models](https://docs.aws.amazon.com/apigateway/latest/developerguide/models-mappings.html)
