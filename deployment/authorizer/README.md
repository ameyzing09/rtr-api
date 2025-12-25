# Lambda Authorizer Infrastructure

AWS Lambda authorizer for JWT validation with Cognito following the ConnectX pattern.

## Architecture

**ConnectX Pattern**: Shared Lambda authorizer validates JWT tokens for all API Gateway endpoints.

### Key Features

- **Free Tier Optimized**: 1M requests + 400K GB-seconds/month FREE
- **JWT Validation**: Verifies Cognito JWT tokens
- **Multi-Tenant Support**: Extracts `tenantId` from custom claims
- **IAM Policy Generation**: Returns Allow/Deny policy for API Gateway
- **Caching**: API Gateway caches authorization decisions (5-10 min)
- **CloudWatch Logging**: Request/response logging
- **X-Ray Tracing**: Optional performance monitoring

## Cost Breakdown

### Lambda Free Tier (Forever)
- **1 million requests/month**: FREE
- **400,000 GB-seconds compute/month**: FREE
- Includes: Function execution, logging, monitoring

### After Free Tier
- **Requests**: $0.20 per 1 million requests
- **Compute**: $0.0000166667 per GB-second

### Example Monthly Cost (256MB, 100ms execution)

| Requests | Compute (GB-s) | Requests Cost | Compute Cost | Total |
|----------|----------------|---------------|--------------|-------|
| 1M       | 25,600         | FREE          | FREE         | $0    |
| 10M      | 256,000        | $1.80         | FREE         | $1.80 |
| 100M     | 2,560,000      | $19.80        | $36.01       | $55.81|

**With API Gateway Caching (5 min TTL)**: Reduces Lambda invocations by ~95%

## Why Lambda Authorizer?

Chosen over Cognito authorizer for:

1. **Custom Logic**: Validate custom `tenantId` claim
2. **Flexibility**: Add custom authorization rules
3. **Multi-Tenant**: Extract and validate tenant context
4. **Caching**: Cache authorization decisions
5. **Cost**: Free for typical usage with caching

## Environment Configurations

### Dev
```hcl
authorizer_memory = 256              # Minimum
authorizer_log_level = "DEBUG"       # Verbose
enable_xray_tracing = false          # Cost savings
enable_reserved_concurrency = false
lambda_s3_bucket = null              # Local ZIP file
```

### PPE
```hcl
authorizer_memory = 512              # More memory
authorizer_log_level = "INFO"
enable_xray_tracing = true           # Enable monitoring
enable_reserved_concurrency = false
lambda_s3_bucket = "rtr-ppe-lambda-artifacts"
```

### Prod
```hcl
authorizer_memory = 512
authorizer_log_level = "INFO"
enable_xray_tracing = true
enable_reserved_concurrency = true   # Reserve capacity
reserved_concurrent_executions = 100
lambda_s3_bucket = "rtr-prod-lambda-artifacts"
```

## Directory Structure

```
deployment/authorizer/
├── README.md
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
    ├── data.tf                # Reference general/cognito modules
    ├── lambda.tf              # Lambda function + alarms
    └── outputs.tf             # Output values
```

## Lambda Handler

### Expected Behavior

The Lambda function must:

1. **Extract JWT** from `Authorization` header
2. **Validate signature** against Cognito JWKS
3. **Verify claims**: issuer, expiration, audience
4. **Extract tenantId** from custom claims
5. **Return IAM policy** (Allow/Deny)

### Request Event (REQUEST Authorizer)

```json
{
  "type": "REQUEST",
  "methodArn": "arn:aws:execute-api:ap-south-1:123456789012:abcdefg1h2/dev/POST/jobs",
  "requestContext": {
    "accountId": "123456789012",
    "apiId": "abcdefg1h2",
    "domainName": "abcdefg1h2.execute-api.ap-south-1.amazonaws.com",
    "requestId": "request-id",
    "httpMethod": "POST",
    "path": "/dev/jobs",
    "stage": "dev"
  },
  "headers": {
    "Authorization": "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "Content-Type": "application/json"
  }
}
```

### Response Format (IAM Policy)

```json
{
  "principalId": "user-uuid",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "execute-api:Invoke",
        "Effect": "Allow",
        "Resource": "arn:aws:execute-api:ap-south-1:123456789012:abcdefg1h2/*"
      }
    ]
  },
  "context": {
    "userId": "user-uuid",
    "tenantId": "tenant-123",
    "email": "user@example.com",
    "roles": "admin,user"
  }
}
```

### Handler Implementation (TypeScript Example)

```typescript
// src/index.ts
import { APIGatewayRequestAuthorizerEvent, APIGatewayAuthorizerResult } from 'aws-lambda';
import { CognitoJwtVerifier } from 'aws-jwt-verify';

// Create JWT verifier
const verifier = CognitoJwtVerifier.create({
  userPoolId: process.env.COGNITO_USER_POOL_ID!,
  tokenUse: 'id',
  clientId: process.env.COGNITO_APP_CLIENT_ID!,
});

export const handler = async (
  event: APIGatewayRequestAuthorizerEvent
): Promise<APIGatewayAuthorizerResult> => {
  try {
    // Extract JWT from Authorization header
    const token = event.headers?.Authorization?.replace('Bearer ', '');

    if (!token) {
      console.error('No token provided');
      throw new Error('Unauthorized');
    }

    // Verify JWT
    const payload = await verifier.verify(token);

    // Extract custom claims
    const userId = payload.sub;
    const email = payload.email;
    const tenantId = payload['custom:tenantId'];

    if (!tenantId) {
      console.error('No tenantId in token');
      throw new Error('Unauthorized');
    }

    // Generate Allow policy
    return generatePolicy(userId, 'Allow', event.methodArn, {
      userId,
      tenantId,
      email: email as string,
    });
  } catch (error) {
    console.error('Authorization failed:', error);
    throw new Error('Unauthorized');  // API Gateway returns 401
  }
};

function generatePolicy(
  principalId: string,
  effect: 'Allow' | 'Deny',
  resource: string,
  context: Record<string, string>
): APIGatewayAuthorizerResult {
  return {
    principalId,
    policyDocument: {
      Version: '2012-10-17',
      Statement: [
        {
          Action: 'execute-api:Invoke',
          Effect: effect,
          Resource: resource.replace(/\/[^/]+$/, '/*'),  // Allow all methods
        },
      ],
    },
    context,
  };
}
```

## Deployment

### Prerequisites

1. **Deploy general infrastructure first** (VPC, IAM, S3)
   ```bash
   cd deployment/general/environments/dev
   terraform init && terraform apply
   ```

2. **Deploy Cognito** (User Pool)
   ```bash
   cd deployment/cognito/environments/dev
   terraform init && terraform apply
   ```

3. **Build Lambda function** (TypeScript → ZIP)
   ```bash
   cd src/authorizer
   npm install
   npm run build
   cd ../../
   mkdir -p dist/authorizer
   cd dist/authorizer
   # Copy built files
   cp -r ../../src/authorizer/dist/* .
   cp -r ../../src/authorizer/node_modules .
   # Create ZIP
   zip -r lambda.zip .
   ```

4. **Update Cognito values** in deployment/authorizer/environments/dev/main.tf
   ```hcl
   jwt_user_pool_id = "ap-south-1_ABC123"  # From Cognito output
   jwt_user_pool_client_id = "1234567890abcdef"
   jwt_issuer = "https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_ABC123"
   ```

### Deploy with Terraform

```bash
# Dev environment
cd deployment/authorizer/environments/dev
terraform init
terraform plan
terraform apply

# Get Lambda ARN
terraform output authorizer_invoke_arn
# Output: arn:aws:apigateway:ap-south-1:lambda:path/.../rtr-dev-authorizer/invocations
```

### Test the Authorizer

```bash
# Get function URL (dev only)
FUNCTION_URL=$(terraform output -raw authorizer_function_url)

# Test with mock event
curl -X POST $FUNCTION_URL \
  -H "Content-Type: application/json" \
  -d '{
    "type": "REQUEST",
    "methodArn": "arn:aws:execute-api:ap-south-1:123:abc/dev/POST/jobs",
    "headers": {
      "Authorization": "Bearer YOUR_JWT_TOKEN"
    }
  }'
```

## Integration with API Gateway

### Update API Gateway Configuration

After deploying the authorizer, update `deployment/api-gateway/environments/dev/main.tf`:

```hcl
# Enable authorizer
enable_authorizer = true

# Set authorizer ARN
authorizer_lambda_arn = "arn:aws:lambda:ap-south-1:ACCOUNT:function:rtr-dev-authorizer"
```

Then redeploy API Gateway:

```bash
cd deployment/api-gateway/environments/dev
terraform apply
```

### Verify Integration

```bash
# Get API Gateway URL
API_URL=$(cd deployment/api-gateway/environments/dev && terraform output -raw api_gateway_url)

# Test health endpoint (no auth)
curl $API_URL/health

# Test with JWT token
curl -X POST $API_URL/jobs \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Job"}'
```

## Monitoring

### CloudWatch Metrics

- **Invocations**: Number of authorizer invocations
- **Errors**: Authorization failures
- **Throttles**: Rate limit exceeded
- **Duration**: Execution time
- **ConcurrentExecutions**: Current concurrent executions

### CloudWatch Alarms

Created automatically:
- **Errors**: > 10 in 5 minutes
- **Throttles**: > 5 in 5 minutes
- **Duration**: > 3 seconds average

### CloudWatch Logs

```
/aws/lambda/rtr-{env}-authorizer
```

Log example:
```
2024-01-01T12:00:00.000Z  INFO  Token validated for user: user-123
2024-01-01T12:00:00.100Z  INFO  TenantId extracted: tenant-456
2024-01-01T12:00:00.150Z  INFO  Policy generated: Allow
```

### X-Ray Tracing (PPE/Prod)

View in AWS Console:
1. X-Ray → Service Map
2. See authorizer→Cognito→JWT validation flow
3. Identify bottlenecks and errors

## Caching Strategy

### API Gateway Caching

API Gateway caches authorizer responses:

```hcl
# In deployment/api-gateway/
authorizer_cache_ttl = 300  # 5 minutes
```

**Benefits**:
- Reduces Lambda invocations by ~95%
- Improves latency (cache hit: <1ms vs Lambda: 50-100ms)
- Saves costs (~$50/month for 100M requests)

**Trade-offs**:
- User changes (role update, logout) take up to 5 min to propagate
- Shorter TTL = more secure but more expensive

### Optimal TTL by Environment

| Environment | TTL   | Reason |
|-------------|-------|--------|
| Dev         | 300s  | Balance testing vs cost |
| PPE         | 300s  | Realistic caching behavior |
| Prod        | 600s  | Maximize cost savings |

## Security Best Practices

1. **Validate JWT signature**: Always verify against Cognito JWKS
2. **Check expiration**: Reject expired tokens
3. **Verify issuer**: Ensure token from correct Cognito pool
4. **Validate audience**: Check `clientId` matches app client
5. **Extract tenantId**: Always validate tenant context
6. **Log failures**: Log all authorization failures for audit
7. **Use IAM roles**: Lambda uses shared execution role from general module
8. **No VPC needed**: Authorizer is stateless, doesn't need database access

## Troubleshooting

### Common Issues

1. **401 Unauthorized**: Authorizer rejecting tokens
   - Check JWT is valid (not expired)
   - Verify Cognito configuration
   - Check CloudWatch logs for errors
   - Test with `aws cognito-idp initiate-auth`

2. **500 Internal Server Error**: Lambda execution error
   - Check Lambda logs in CloudWatch
   - Verify environment variables
   - Check IAM role permissions
   - Test Lambda directly with function URL (dev)

3. **Long latency**: Slow authorization
   - Check Lambda memory (512MB recommended)
   - Enable provisioned concurrency (prod)
   - Verify API Gateway caching is enabled
   - Check X-Ray traces for bottlenecks

4. **Throttling**: Too many invocations
   - Increase reserved concurrency (prod)
   - Increase API Gateway cache TTL
   - Check for authorization loops

### Testing Locally

```bash
# Install AWS SAM CLI
brew install aws-sam-cli  # or appropriate package manager

# Test locally
sam local invoke AuthorizerFunction \
  --event events/test-event.json \
  --env-vars env.json
```

## Cost Optimization Tips

1. **Enable API Gateway caching**: Reduces Lambda invocations by 95%
2. **Right-size memory**: 256MB for dev, 512MB for prod
3. **Use reserved concurrency**: Prevent runaway costs in prod
4. **Monitor CloudWatch**: Set billing alarms
5. **Optimize code**: Faster execution = lower cost

## Deployment Order

```
1. deployment/general/      (VPC, IAM, Secrets)
2. deployment/cognito/      (User Pool)
3. deployment/authorizer/   (This module)
4. deployment/api-gateway/  (REST API with authorizer)
5. apps/*/deploy/           (App routes)
```

## Next Steps

After deploying the authorizer:

1. **Build Lambda function**: Create TypeScript handler with JWT validation
2. **Test locally**: Use SAM CLI to test authorization logic
3. **Deploy to dev**: Deploy with local ZIP file
4. **Update API Gateway**: Enable authorizer in deployment/api-gateway/
5. **Test integration**: Verify end-to-end with Cognito tokens
6. **Set up CI/CD**: GitHub Actions to build and deploy automatically

## Resources

- [Lambda Pricing](https://aws.amazon.com/lambda/pricing/)
- [Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [Cognito JWT Verification](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html)
- [aws-jwt-verify Library](https://github.com/awslabs/aws-jwt-verify)
