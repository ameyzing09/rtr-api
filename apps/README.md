# RTR API - App Deployments

This directory contains the AWS Lambda function deployments for the RTR API applications.

## 📁 Structure

```
apps/
├── auth/                    # Authentication service
│   ├── deploy/             # Infrastructure as Code
│   │   ├── environments/   # Environment-specific configs
│   │   │   ├── dev/
│   │   │   ├── ppe/
│   │   │   └── prod/
│   │   └── resources/      # Terraform modules
│   └── src/                # Application code (TODO)
│
├── job/                     # Job management service
│   ├── deploy/             # Infrastructure as Code
│   │   ├── environments/   # Environment-specific configs
│   │   │   ├── dev/
│   │   │   ├── ppe/
│   │   │   └── prod/
│   │   └── resources/      # Terraform modules
│   └── src/                # Application code (TODO)
│
└── authorizer/              # JWT authorizer (in deployment/)
    └── src/                # Application code (TODO)
```

## 🚀 Deployment Order

Apps must be deployed AFTER core infrastructure:

```
1. deployment/firstRunCreateBucket    (ONE-TIME)
2. deployment/general                 (VPC, IAM, Secrets)
3. deployment/database                (RDS PostgreSQL)
4. deployment/cognito                 (User Pool)
5. deployment/authorizer              (JWT validation)
6. deployment/api-gateway             (REST API)
7. apps/auth/deploy                   ⬅️ YOU ARE HERE
8. apps/job/deploy                    ⬅️ YOU ARE HERE
```

## 📋 Prerequisites

Before deploying apps, ensure:

1. ✅ Core infrastructure deployed (steps 1-6 above)
2. ✅ Lambda handler code built: `npm run build auth` or `npx nx build auth`
3. ✅ Lambda ZIP exists: `dist/apps/auth/lambda.zip`
4. ✅ AWS credentials configured
5. ✅ Terraform backend bucket exists (`rtr-terraform-state`)

## 🏗️ App: Auth Service

**Purpose**: User authentication and token management

**API Routes**:
- `POST /auth/login` - Login with Cognito credentials (public)
- `POST /auth/federate` - Federated login (OAuth/SAML) (public)
- `POST /auth/refresh` - Refresh access token (protected)
- `POST /auth/logout` - Logout and invalidate tokens (protected)

**Dependencies**:
- Cognito User Pool (for authentication)
- RDS PostgreSQL (for user metadata)
- Secrets Manager (for JWT keys)
- API Gateway (for routing)
- Lambda Authorizer (for protected routes)

**Configuration**:
- **Dev**: 512 MB memory, 30s timeout, DEBUG logging
- **PPE**: 512 MB memory, 30s timeout, INFO logging
- **Prod**: 1024 MB memory, 30s timeout, INFO logging, X-Ray, Alarms

### Deploy Auth (Dev)

```bash
# 1. Build Lambda function
cd /path/to/rtr-api
npx nx build auth

# Verify lambda.zip exists
ls -lh dist/apps/auth/lambda.zip

# 2. Deploy infrastructure
cd apps/auth/deploy/environments/dev

# Initialize Terraform (first time only)
terraform init

# Review changes
terraform plan

# Deploy
terraform apply

# 3. Get outputs
terraform output

# Example outputs:
# login_endpoint = "https://abc123.execute-api.ap-south-1.amazonaws.com/dev/auth/login"
# federate_endpoint = "https://abc123.execute-api.ap-south-1.amazonaws.com/dev/auth/federate"
```

### Test Auth Endpoints

```bash
# Get the login endpoint
LOGIN_URL=$(terraform output -raw login_endpoint)

# Test login (replace with actual Cognito user)
curl -X POST $LOGIN_URL \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser@example.com",
    "password": "Test123!"
  }'

# Expected response:
# {
#   "accessToken": "eyJraWQiOiI...",
#   "refreshToken": "eyJjdHkiOi...",
#   "expiresIn": 3600,
#   "tokenType": "Bearer"
# }
```

## 🏗️ App: Job Service

**Purpose**: Job/task management with multi-tenant support

**API Routes**:
- `GET /jobs` - List all jobs (filtered by tenant)
- `POST /jobs` - Create new job
- `GET /jobs/{id}` - Get job by ID
- `PUT /jobs/{id}` - Update job
- `DELETE /jobs/{id}` - Delete job

**All routes are protected** (require JWT authentication)

**Dependencies**:
- RDS PostgreSQL (for job data)
- API Gateway (for routing)
- Lambda Authorizer (for JWT validation)
- VPC (for database access)

**Configuration**:
- **Dev**: 512 MB memory, 30s timeout, DEBUG logging
- **PPE**: 512 MB memory, 30s timeout, INFO logging
- **Prod**: 1024 MB memory, 30s timeout, INFO logging, X-Ray, Alarms

### Deploy Job (Dev)

```bash
# 1. Build Lambda function
cd /path/to/rtr-api
npx nx build job

# Verify lambda.zip exists
ls -lh dist/apps/job/lambda.zip

# 2. Deploy infrastructure
cd apps/job/deploy/environments/dev

# Initialize Terraform (first time only)
terraform init

# Review changes
terraform plan

# Deploy
terraform apply

# 3. Get outputs
terraform output

# Example outputs:
# jobs_endpoint_url = "https://abc123.execute-api.ap-south-1.amazonaws.com/dev/jobs"
```

### Test Job Endpoints

```bash
# Get endpoints
JOBS_URL=$(terraform output -raw jobs_endpoint_url)

# Get access token from auth service
ACCESS_TOKEN="<token from /auth/login>"

# List jobs (empty initially)
curl -X GET $JOBS_URL \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# Create job
curl -X POST $JOBS_URL \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Job",
    "description": "My first job",
    "status": "pending"
  }'

# Get job by ID
JOB_ID="<id from create response>"
curl -X GET $JOBS_URL/$JOB_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN"

# Update job
curl -X PUT $JOBS_URL/$JOB_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "completed"
  }'

# Delete job
curl -X DELETE $JOBS_URL/$JOB_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

## 🔄 GitHub Actions Deployment

You can also deploy via GitHub Actions:

```yaml
# .github/workflows/deploy.yml

# Manual workflow dispatch
1. Go to: GitHub → Actions → "Deploy Infrastructure"
2. Select:
   - Target: "auth" or "job"
   - Environment: "dev", "ppe", or "prod"
3. Click "Run workflow"
4. Wait for deployment to complete
5. Check outputs in job summary
```

**Workflow steps**:
1. Builds Lambda function (npm install + npx nx build)
2. Creates lambda.zip
3. Uploads to S3 or local deployment
4. Runs Terraform init/plan/apply
5. Outputs endpoint URLs
6. Runs smoke tests (dev only)

## 🔧 Configuration TODOs

Before deploying, update these values:

### 1. AWS Account ID

```bash
# Get your AWS account ID
aws sts get-caller-identity --query Account --output text

# Update in all environment files:
# - apps/auth/deploy/environments/dev/main.tf
# - apps/auth/deploy/environments/ppe/main.tf
# - apps/auth/deploy/environments/prod/main.tf
# - apps/job/deploy/environments/dev/main.tf
# - apps/job/deploy/environments/ppe/main.tf
# - apps/job/deploy/environments/prod/main.tf

# Replace:
aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO
# With:
aws_account_id = "123456789012"
```

## 🏢 Multi-Tenancy

Both apps support multi-tenancy via:

1. **JWT Token**: Contains `custom:tenantId` claim (extracted by authorizer)
2. **Request Context**: Authorizer adds `tenantId` to API Gateway context
3. **Lambda Handler**: Receives `tenantId` from event context
4. **Database Queries**: All queries filter by `WHERE tenantId = ?`

**Example Lambda Event**:
```json
{
  "requestContext": {
    "authorizer": {
      "tenantId": "tenant-123",
      "userId": "user-456",
      "principalId": "user-456"
    }
  },
  "httpMethod": "GET",
  "path": "/jobs"
}
```

## 📊 CloudWatch Logs

View Lambda logs:

```bash
# Auth logs
aws logs tail /aws/lambda/rtr-dev-auth --follow

# Job logs
aws logs tail /aws/lambda/rtr-dev-job --follow

# API Gateway access logs
aws logs tail /aws/apigateway/rtr-dev-auth --follow
aws logs tail /aws/apigateway/rtr-dev-job --follow
```

## 🚨 Troubleshooting

### Lambda function not found

**Error**: `Error: data source not found`

**Solution**: Ensure core infrastructure is deployed first:
```bash
cd deployment/general/environments/dev && terraform apply
cd deployment/database/environments/dev && terraform apply
cd deployment/api-gateway/environments/dev && terraform apply
```

### Lambda can't connect to database

**Error**: `Connection timeout`

**Solution**:
1. Check VPC configuration: `enable_vpc = true`
2. Check security groups allow Lambda → RDS
3. Check Lambda is in private subnets
4. Check NAT gateway is configured

### Authorizer not working

**Error**: `Unauthorized` or `Missing Authentication Token`

**Solution**:
1. Deploy authorizer first: `cd deployment/authorizer/environments/dev && terraform apply`
2. Check API Gateway has authorizer configured
3. Test JWT token is valid: `jwt.io`
4. Check Cognito User Pool ID is correct

### CORS errors

**Error**: `Access to fetch blocked by CORS policy`

**Solution**:
1. Check OPTIONS methods are deployed (CORS preflight)
2. Check `Access-Control-Allow-Origin` header is set
3. Verify `API_URL` environment variable matches your domain

## 📚 Resources

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [API Gateway REST API](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Nx Build System](https://nx.dev/)

## 🎯 Next Steps

After deploying both apps:

1. ✅ Test authentication flow end-to-end
2. ✅ Create database migrations (TypeORM)
3. ✅ Implement Lambda handler code
4. ✅ Add integration tests
5. ✅ Deploy to PPE environment
6. ✅ User acceptance testing
7. ✅ Deploy to PROD environment

**Status**: App deployment infrastructure COMPLETE! ✅
