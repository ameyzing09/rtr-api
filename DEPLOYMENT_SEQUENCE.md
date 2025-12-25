# RTR API Deployment Sequence

Complete deployment guide for RTR API infrastructure and Lambda applications.

## Prerequisites

- AWS CLI configured with credentials for account `037610439839`
- Terraform 1.5.7+ installed
- Node.js 18.x installed
- Access to `rtr-api-deployer` IAM user with PowerUserAccess + custom inline policy

## Deployment Status

### ✅ Already Deployed (5/8 modules):

1. **Terraform State Backend** - `deployment/firstRunCreateBucket/dev`
   - S3 Bucket: `rtr-tfstate`
   - DynamoDB Table: `rtr-terraform-locks`

2. **General Infrastructure** - `deployment/general/environments/dev`
   - VPC with public/private subnets (ap-south-1a, ap-south-1b)
   - NAT Gateways (2)
   - IAM roles for Lambda
   - S3 buckets: `rtr-dev-artifacts`, `rtr-dev-lambda-code`
   - Secrets Manager
   - CloudWatch log groups

3. **Cognito User Pool** - `deployment/cognito/environments/dev`
   - User Pool ID: `ap-south-1_cxbuwKQks`
   - App Client ID: `69q6o2lsqid3nhq8up8g6k6j4v`
   - Custom attribute: `custom:tenantId`

4. **RDS Database** - `deployment/database/environments/dev`
   - Endpoint: `rtr-dev-db.c1uywk8g8oxm.ap-south-1.rds.amazonaws.com:5432`
   - Database: `rtr_db`
   - Username: `rtr_admin`
   - Engine: PostgreSQL 18.1
   - Instance: db.t3.micro (FREE tier)

5. **Authorizer Lambda** - `deployment/authorizer/environments/dev`
   - Function: `rtr-dev-authorizer`
   - Infrastructure deployed (needs code update)

### ❌ Not Yet Deployed (3 modules):

6. **API Gateway** - `deployment/api-gateway/environments/dev`
7. **Auth Lambda** - `apps/auth/deploy/environments/dev`
8. **Job Lambda** - `apps/job/deploy/environments/dev`

---

## First-Time Deployment (Manual)

### Step 1: Deploy API Gateway Infrastructure

```bash
cd deployment/api-gateway/environments/dev
terraform init
terraform apply
```

**What this creates:**
- REST API Gateway: `rtr-dev-api`
- `/health` endpoint (MOCK integration)
- CloudWatch logs and alarms
- API Gateway stage: `dev`

**Expected output:**
```
api_gateway_id = "xyz123abc"
api_gateway_endpoint = "https://xyz123abc.execute-api.ap-south-1.amazonaws.com/dev"
invoke_url = "https://xyz123abc.execute-api.ap-south-1.amazonaws.com/dev"
```

**Test:**
```bash
curl https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/health
# Should return: {"status": "healthy"}
```

### Step 2: Build Lambda Deployment Packages (First Time Only)

```bash
# Auth Lambda
cd apps/auth/src
npm install --production
zip -r ../lambda.zip .
cd ../../..

# Authorizer Lambda
cd apps/authorizer/src
npm install --production
zip -r ../lambda.zip .
cd ../../..

# Job Lambda
cd apps/job/src
npm install --production
zip -r ../lambda.zip .
cd ../../..
```

**Verify ZIPs created:**
```bash
ls -lh apps/auth/lambda.zip
ls -lh apps/authorizer/lambda.zip
ls -lh apps/job/lambda.zip
```

### Step 3: Deploy Auth Lambda Infrastructure + Code

```bash
cd apps/auth/deploy/environments/dev
terraform init
terraform apply
```

**What this creates:**
- Lambda function: `rtr-dev-auth`
- API Gateway routes:
  - `POST /auth/login`
  - `POST /auth/federate`
  - `POST /auth/refresh`
  - `POST /auth/logout`
- Lambda permission for API Gateway to invoke
- CloudWatch log group: `/aws/lambda/rtr-dev-auth`

**Test:**
```bash
curl -X POST https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "test@example.com", "password": "Test123!"}'
```

### Step 4: Deploy Job Lambda Infrastructure + Code

```bash
cd apps/job/deploy/environments/dev
terraform init
terraform apply
```

**What this creates:**
- Lambda function: `rtr-dev-job`
- API Gateway routes:
  - `GET /jobs`
  - `POST /jobs`
  - `GET /jobs/{id}`
  - `PUT /jobs/{id}`
  - `DELETE /jobs/{id}`
- VPC configuration for RDS access
- Security group rules for database connection
- CloudWatch log group: `/aws/lambda/rtr-dev-job`

**Test:**
```bash
# List jobs (requires auth token)
curl -X GET https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/jobs \
  -H "Authorization: Bearer <token>"
```

---

## Future Deployments (GitHub Actions)

After initial deployment, use GitHub Actions for Lambda code updates.

### Option A: Automatic Deployment (Git Push)

Push code changes to main branch:

```bash
git add apps/auth/src/
git commit -m "Update auth Lambda handler"
git push origin main
```

GitHub Actions automatically:
1. Detects changes in `apps/auth/**`
2. Runs workflow `.github/workflows/deploy-auth.yml`
3. Installs dependencies
4. Runs tests
5. Creates ZIP package
6. Uploads to S3
7. Updates Lambda function code

### Option B: Manual Trigger (GitHub UI)

1. Go to **Actions** tab in GitHub
2. Select workflow (e.g., "Deploy Auth Lambda")
3. Click **Run workflow**
4. Select environment: `dev`, `ppe`, or `prod`
5. Click **Run workflow**

### Option C: Manual Trigger (CLI)

Install GitHub CLI:
```bash
# Windows
winget install --id GitHub.cli

# macOS
brew install gh

# Authenticate
gh auth login
```

Trigger workflows:
```bash
# Deploy auth to dev
gh workflow run "deploy-auth.yml" --field environment=dev

# Deploy job to ppe
gh workflow run "deploy-job.yml" --field environment=ppe

# Deploy authorizer to prod
gh workflow run "deploy-authorizer.yml" --field environment=prod
```

---

## Infrastructure Updates (Terraform Changes)

When updating infrastructure (not just Lambda code):

### Update Lambda Configuration (Memory, Timeout, etc.)

```bash
# Example: Update auth Lambda memory
cd apps/auth/deploy/environments/dev
# Edit main.tf - change memory_size or timeout
terraform plan
terraform apply
```

### Update API Gateway Routes

```bash
# Example: Add new route to auth
cd apps/auth/deploy/environments/dev
# Edit resources/api_gateway.tf - add new route
terraform plan
terraform apply
```

### Update Database Configuration

```bash
cd deployment/database/environments/dev
# Edit main.tf - change instance class, storage, etc.
terraform plan
terraform apply
```

---

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────┐
│ GitHub Repository (rtr-api)                             │
│                                                          │
│  ┌──────────────────┐      ┌─────────────────────────┐ │
│  │ Infrastructure   │      │ Lambda Applications     │ │
│  │ (Terraform)      │      │ (Node.js + Terraform)   │ │
│  │                  │      │                         │ │
│  │ - general        │      │ - apps/auth             │ │
│  │ - database       │      │ - apps/authorizer       │ │
│  │ - cognito        │      │ - apps/job              │ │
│  │ - api-gateway    │      │                         │ │
│  │ - authorizer     │      │                         │ │
│  └──────────────────┘      └─────────────────────────┘ │
│           │                           │                 │
│           │                           │                 │
└───────────┼───────────────────────────┼─────────────────┘
            │                           │
            │                           │
            ▼                           ▼
    Manual Terraform          GitHub Actions Workflows
    (First-time setup)        (.github/workflows/)
            │                           │
            │                           │
            └──────────┬────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │  AWS Resources       │
            │  (ap-south-1)        │
            │                      │
            │  - VPC & Networking  │
            │  - RDS PostgreSQL    │
            │  - Cognito           │
            │  - API Gateway       │
            │  - Lambda Functions  │
            │  - S3, Secrets, etc. │
            └──────────────────────┘
```

---

## Environment Promotion

### dev → ppe

```bash
# 1. Test in dev thoroughly
# 2. Deploy infrastructure to ppe
cd deployment/api-gateway/environments/ppe
terraform init && terraform apply

cd apps/auth/deploy/environments/ppe
terraform init && terraform apply

cd apps/job/deploy/environments/ppe
terraform init && terraform apply

# 3. Trigger Lambda updates via GitHub Actions
gh workflow run "deploy-auth.yml" --field environment=ppe
gh workflow run "deploy-job.yml" --field environment=ppe
```

### ppe → prod

```bash
# Same pattern, use prod environment
gh workflow run "deploy-auth.yml" --field environment=prod
gh workflow run "deploy-job.yml" --field environment=prod
```

---

## Rollback Procedure

### Rollback Lambda Code

```bash
# List recent versions
aws lambda list-versions-by-function \
  --function-name rtr-dev-auth \
  --region ap-south-1

# Rollback to specific version
aws lambda update-alias \
  --function-name rtr-dev-auth \
  --name dev \
  --function-version <previous-version> \
  --region ap-south-1
```

### Rollback Infrastructure

```bash
# Use Terraform state to rollback
cd apps/auth/deploy/environments/dev
terraform state pull > backup.tfstate
# Restore previous state if needed
terraform state push backup.tfstate
```

---

## Monitoring & Logs

### View Lambda Logs

```bash
# Auth Lambda
aws logs tail /aws/lambda/rtr-dev-auth --follow --region ap-south-1

# Job Lambda
aws logs tail /aws/lambda/rtr-dev-job --follow --region ap-south-1

# Authorizer Lambda
aws logs tail /aws/lambda/rtr-dev-authorizer --follow --region ap-south-1
```

### Check API Gateway Metrics

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=rtr-dev-api \
  --start-time 2025-11-17T00:00:00Z \
  --end-time 2025-11-17T23:59:59Z \
  --period 3600 \
  --statistics Sum \
  --region ap-south-1
```

---

## Cost Monitoring

### Current Monthly Costs (dev environment):

| Resource | Cost |
|----------|------|
| VPC | FREE |
| NAT Gateways (2) | ~$70/month |
| RDS db.t3.micro | FREE (first 12 months) |
| Cognito | FREE (under 50K MAU) |
| Lambda | FREE (under 1M requests) |
| S3 | ~$0.05/month |
| Secrets Manager | ~$0.80/month |
| **Total** | **~$71/month** |

### Cost Optimization:

To reduce NAT Gateway costs (~$70/month):
1. Use single NAT Gateway instead of 2 (loses HA)
2. Use VPC endpoints for AWS services
3. Consider NAT instances (cheaper but more management)

---

## Troubleshooting

### Lambda can't connect to RDS

```bash
# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rtr-dev-vpc-lambda-sg" \
  --region ap-south-1

# Check Lambda VPC configuration
aws lambda get-function-configuration \
  --function-name rtr-dev-job \
  --region ap-south-1 | jq '.VpcConfig'
```

### API Gateway returns 403

- Check Lambda permissions for API Gateway
- Verify authorizer is properly configured
- Check CloudWatch logs for Lambda authorizer

### Terraform state locked

```bash
# Check DynamoDB for lock
aws dynamodb scan \
  --table-name rtr-terraform-locks \
  --region ap-south-1

# Force unlock (use carefully)
cd <terraform-directory>
terraform force-unlock <lock-id>
```

---

## Next Steps

1. **Database Schema**: Create tables for users and jobs
2. **Real Authentication**: Implement actual Cognito integration in auth Lambda
3. **Database Queries**: Implement PostgreSQL queries in job Lambda
4. **Tests**: Add unit tests for Lambda handlers
5. **Monitoring**: Set up CloudWatch dashboards and alarms
6. **CI/CD**: Consider adding pre-deployment validation

---

## Support & Documentation

- **AWS Region**: ap-south-1 (Mumbai)
- **AWS Account**: 037610439839
- **GitHub Repo**: https://github.com/yourusername/rtr-api
- **Terraform State**: s3://rtr-tfstate/
