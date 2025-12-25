# RTR API Deployment Guide

Complete guide for deploying infrastructure and Lambda applications using GitHub Actions + Terraform.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment Architecture](#deployment-architecture)
- [First-Time Setup](#first-time-setup)
- [Daily Workflows](#daily-workflows)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Design Principles

1. **Terraform is Source of Truth** - All AWS resources managed by Terraform (no manual changes)
2. **Manual Deployments Only** - All deployments triggered manually (no auto-deploy on push)
3. **Deploy Components Individually** - Each module/app can be deployed separately
4. **Simple and Testable** - Clear workflows, easy to understand and test

### Technology Stack

- **Infrastructure as Code**: Terraform 1.5.7
- **CI/CD**: GitHub Actions
- **Cloud Provider**: AWS (ap-south-1 / Mumbai region)
- **Lambda Runtime**: Node.js 18.x
- **Database**: PostgreSQL 18.1 on RDS
- **Authentication**: AWS Cognito

---

## Prerequisites

### 1. Install Required Tools

```bash
# GitHub CLI (for triggering workflows)
# Windows
winget install --id GitHub.cli

# macOS
brew install gh

# Linux
# See https://github.com/cli/cli/blob/trunk/docs/install_linux.md

# Authenticate with GitHub
gh auth login
```

### 2. AWS Credentials

Ensure GitHub repository secrets are configured:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

IAM user: `rtr-api-deployer`
Permissions: PowerUserAccess + custom inline policy for Terraform state

### 3. Terraform State Backend

Already deployed:
- S3 Bucket: `rtr-tfstate`
- DynamoDB Table: `rtr-terraform-locks`

---

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Developer                                                   │
│    │                                                         │
│    ├─> ./nx deploy auth dev         (Deploy Lambda)         │
│    ├─> ./nx deploy api-gateway dev  (Deploy Infrastructure) │
│    └─> ./nx test dev                (Run Tests)             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  GitHub Actions       │
              │                       │
              │  1. Build Lambda ZIP  │
              │  2. Run Tests         │
              │  3. Terraform Plan    │
              │  4. Terraform Apply   │
              └──────────┬────────────┘
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
              └──────────────────────┘
```

### Components

**Infrastructure Modules** (deployment/):
- **general** - VPC, IAM roles, S3 buckets, Secrets Manager
- **database** - RDS PostgreSQL
- **cognito** - User Pool with custom tenantId attribute
- **authorizer** - Lambda authorizer infrastructure only
- **api-gateway** - REST API Gateway with /health endpoint

**Lambda Applications** (apps/):
- **auth** - Authentication service (login, refresh, logout)
- **authorizer** - JWT token validator for API Gateway
- **job** - Job management CRUD operations

---

## First-Time Setup

### Deployment Status

✅ **Already Deployed:**
1. Terraform State Backend
2. General Infrastructure (VPC, IAM, S3)
3. Database (RDS PostgreSQL)
4. Cognito (User Pool)
5. Authorizer (Lambda infrastructure)

❌ **Not Yet Deployed:**
6. API Gateway
7. Auth Lambda
8. Job Lambda

### Step-by-Step Deployment

#### Step 1: Deploy API Gateway

```bash
./nx deploy api-gateway dev
```

**What this creates:**
- REST API Gateway: `rtr-dev-api`
- `/health` endpoint (MOCK integration)
- CloudWatch logs and alarms

**Verify:**
```bash
# Get API Gateway URL from workflow outputs
curl https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/health
# Expected: {"status": "healthy"}
```

#### Step 2: Deploy Auth Lambda

```bash
./nx deploy auth dev
```

**What this creates:**
- Lambda function: `rtr-dev-auth`
- API Gateway routes: `/auth/login`, `/auth/refresh`, `/auth/logout`
- Lambda permissions for API Gateway

**Verify:**
```bash
curl -X POST https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "test@example.com", "password": "Test123!"}'
```

#### Step 3: Deploy Job Lambda

```bash
./nx deploy job dev
```

**What this creates:**
- Lambda function: `rtr-dev-job`
- API Gateway routes: `/jobs` (GET, POST, PUT, DELETE)
- VPC configuration for RDS access

**Verify:**
```bash
# List jobs (requires auth token)
curl -X GET https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/jobs \
  -H "Authorization: Bearer <token>"
```

#### Step 4: Run Integration Tests

```bash
./nx test dev
```

**What this tests:**
- Health endpoint
- Authentication flow
- Job CRUD operations
- Database connectivity

---

## Daily Workflows

### Deploy a Lambda Application

```bash
# Syntax: ./nx deploy <app> <environment>

# Deploy to dev
./nx deploy auth dev
./nx deploy authorizer dev
./nx deploy job dev

# Deploy to ppe (requires manual approval in GitHub)
./nx deploy auth ppe

# Deploy to prod (requires manual approval in GitHub)
./nx deploy job prod
```

**What happens:**
1. Workflow triggered in GitHub Actions
2. Lambda code built (npm install + zip)
3. Tests run (npm test)
4. ZIP placed in correct location
5. Terraform init/plan/apply
6. Lambda function updated
7. Deployment summary displayed

### Deploy Infrastructure Module

```bash
# Syntax: ./nx deploy <module> <environment>

# Deploy infrastructure
./nx deploy general dev
./nx deploy database dev
./nx deploy cognito dev
./nx deploy api-gateway dev
```

**What happens:**
1. Workflow triggered in GitHub Actions
2. Terraform init/validate
3. Terraform plan
4. Terraform apply
5. Outputs saved as artifacts

### Run Tests

```bash
# Syntax: ./nx test <environment>

./nx test dev      # Run tests on dev
./nx test ppe      # Run tests on ppe
./nx test prod     # Run tests on prod
```

### Monitor Deployments

```bash
# View recent workflow runs
gh run list --limit 5

# View specific workflow run
gh run view <run-id> --log

# View logs for specific job
gh run view <run-id> --log --job <job-id>
```

---

## nx CLI Reference

### Commands

```bash
./nx deploy <target> [environment]    # Deploy Lambda app or infrastructure
./nx test [environment]               # Run integration tests
./nx help                             # Show help
```

### Deploy Targets

**Lambda Applications:**
- `auth` - Authentication Lambda
- `authorizer` - Lambda Authorizer
- `job` - Job Management Lambda

**Infrastructure Modules:**
- `general` - VPC, IAM, S3, Secrets
- `database` - RDS PostgreSQL
- `cognito` - User Pool
- `api-gateway` - REST API Gateway

### Environments

- `dev` - Development (default)
- `ppe` - Pre-production
- `prod` - Production

### Examples

```bash
# Lambda deployments
./nx deploy auth              # Deploy auth to dev
./nx deploy auth ppe          # Deploy auth to ppe
./nx deploy authorizer prod   # Deploy authorizer to prod

# Infrastructure deployments
./nx deploy api-gateway dev   # Deploy API Gateway to dev
./nx deploy database ppe      # Deploy database to ppe

# Testing
./nx test                     # Run tests on dev
./nx test prod                # Run tests on prod
```

---

## Testing

### Integration Tests

Located in: `.github/workflows/test-integration.yml`

**Test Coverage:**
1. **Health Check** - Verify API Gateway is responding
2. **Authentication** - Test login, token refresh, logout
3. **Job CRUD** - Create, read, update, delete jobs
4. **Database** - Verify RDS connectivity
5. **Cognito** - Test user pool operations

**Running Tests:**

```bash
# Via nx command
./nx test dev

# Via GitHub CLI
gh workflow run test-integration.yml --field environment=dev

# Via GitHub UI
# Actions → test-integration.yml → Run workflow → Select environment
```

### Manual Testing

```bash
# Get API Gateway URL
cd deployment/api-gateway/environments/dev
terraform output api_gateway_endpoint

# Test health endpoint
curl https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/health

# Test auth endpoint
curl -X POST https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "test@example.com", "password": "Test123!"}'

# Test jobs endpoint (with token)
curl https://<api-id>.execute-api.ap-south-1.amazonaws.com/dev/jobs \
  -H "Authorization: Bearer <token>"
```

---

## Environment Progression

### dev → ppe

```bash
# 1. Test thoroughly in dev
./nx test dev

# 2. Deploy to ppe
./nx deploy api-gateway ppe
./nx deploy auth ppe
./nx deploy job ppe

# 3. Test in ppe
./nx test ppe
```

### ppe → prod

```bash
# 1. Test thoroughly in ppe
./nx test ppe

# 2. Deploy to prod (requires approval in GitHub)
./nx deploy auth prod
./nx deploy job prod

# 3. Test in prod
./nx test prod
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

### CloudWatch Metrics

```bash
# API Gateway request count
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=rtr-dev-api \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region ap-south-1

# Lambda invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=rtr-dev-auth \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region ap-south-1
```

### Deployment History

```bash
# View recent workflow runs
gh run list --workflow=deploy-lambda.yml --limit 10

# View specific deployment
gh run view <run-id>

# Download Terraform outputs
gh run download <run-id> --name terraform-outputs-auth-dev
```

---

## Troubleshooting

### Lambda Can't Connect to RDS

**Symptom:** Timeout errors when Lambda tries to access database

**Solutions:**
```bash
# Check Lambda is in VPC
aws lambda get-function-configuration --function-name rtr-dev-job \
  --region ap-south-1 | jq '.VpcConfig'

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rtr-dev-vpc-lambda-sg" \
  --region ap-south-1

# Verify RDS security group allows Lambda SG
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rtr-dev-db-sg" \
  --region ap-south-1 | jq '.SecurityGroups[].IpPermissions'
```

### API Gateway Returns 403

**Symptom:** All API requests return 403 Forbidden

**Solutions:**
```bash
# Check Lambda permissions
aws lambda get-policy --function-name rtr-dev-auth --region ap-south-1

# Check authorizer configuration
aws apigateway get-authorizer \
  --rest-api-id <api-id> \
  --authorizer-id <authorizer-id> \
  --region ap-south-1

# View authorizer logs
aws logs tail /aws/lambda/rtr-dev-authorizer --follow --region ap-south-1
```

### Terraform State Locked

**Symptom:** `Error acquiring state lock`

**Solutions:**
```bash
# Check DynamoDB for lock
aws dynamodb scan \
  --table-name rtr-terraform-locks \
  --region ap-south-1

# Force unlock (use carefully - ensure no other terraform is running)
cd deployment/<module>/environments/<env>
terraform force-unlock <lock-id>
```

### GitHub Actions Workflow Failed

**Symptom:** Workflow run shows red X

**Solutions:**
```bash
# View detailed logs
gh run view <run-id> --log

# Re-run failed jobs
gh run rerun <run-id>

# Re-run only failed jobs
gh run rerun <run-id> --failed
```

### Lambda Package Too Large

**Symptom:** `Unzipped size must be smaller than 262144000 bytes`

**Solutions:**
1. Remove unnecessary dependencies from package.json
2. Use Lambda Layers for shared dependencies
3. Exclude devDependencies (use --production flag)
4. Remove large files (.md, tests, etc.) from ZIP

---

## Cost Monitoring

### Current Monthly Costs (dev environment)

| Resource | Cost (USD) |
|----------|-----------|
| VPC | FREE |
| NAT Gateways (2) | ~$70/month |
| RDS db.t3.micro | FREE (first 12 months) |
| Cognito | FREE (under 50K MAU) |
| Lambda | FREE (under 1M requests) |
| S3 | ~$0.05/month |
| Secrets Manager | ~$0.80/month |
| **Total** | **~$71/month** |

### Cost Optimization Tips

1. **Reduce NAT Gateway costs:**
   - Use single NAT Gateway (loses high availability)
   - Use VPC endpoints for AWS services
   - Consider NAT instances (cheaper but more management)

2. **Monitor Lambda costs:**
   - Set CloudWatch alarms for invocation counts
   - Optimize Lambda memory and timeout settings
   - Use Lambda Insights for detailed metrics

3. **Database optimization:**
   - Use RDS Proxy for connection pooling
   - Enable Multi-AZ only for production
   - Consider Reserved Instances for production

---

## Best Practices

### Infrastructure Changes

1. **Always run terraform plan first**
   ```bash
   cd deployment/<module>/environments/<env>
   terraform plan
   ```

2. **Test in dev before deploying to ppe/prod**

3. **Review changes carefully** - Terraform shows exactly what will change

4. **Keep infrastructure immutable** - Don't make manual changes in AWS Console

### Lambda Development

1. **Test locally before deploying**
   ```bash
   cd apps/auth/src
   npm test
   ```

2. **Keep Lambda functions small** - Single responsibility principle

3. **Use environment variables** - Don't hardcode configuration

4. **Implement proper error handling** - Return meaningful error messages

5. **Add logging** - Use console.log for CloudWatch Logs

### Security

1. **Never commit secrets** - Use AWS Secrets Manager

2. **Follow principle of least privilege** - Minimal IAM permissions

3. **Enable encryption** - RDS, S3, Secrets Manager all encrypted

4. **Use VPC for database** - RDS not publicly accessible

5. **Validate input** - Always validate and sanitize user input

---

## Next Steps

### Short-term

- [ ] Create database schema (users, jobs tables)
- [ ] Implement real Cognito integration in auth Lambda
- [ ] Implement real database queries in job Lambda
- [ ] Add proper error handling and logging
- [ ] Write unit tests for Lambda functions

### Medium-term

- [ ] Add CloudWatch dashboards
- [ ] Implement rate limiting
- [ ] Add request/response validation
- [ ] Create database migrations system
- [ ] Add API documentation (Swagger/OpenAPI)

### Long-term

- [ ] Implement caching (ElastiCache)
- [ ] Add full-text search capabilities
- [ ] Implement audit logging
- [ ] Add performance monitoring (X-Ray)
- [ ] Create disaster recovery plan

---

## Support & Resources

- **AWS Region:** ap-south-1 (Mumbai)
- **AWS Account:** 037610439839
- **Terraform State:** s3://rtr-tfstate/
- **GitHub Repo:** https://github.com/yourusername/rtr-api

### Useful Links

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)

---

## Appendix

### Directory Structure

```
rtr-api/
├── .github/
│   └── workflows/
│       ├── deploy-lambda.yml         # Deploy Lambda applications
│       ├── deploy-infrastructure.yml # Deploy infrastructure modules
│       └── test-integration.yml      # Integration tests
├── deployment/
│   ├── general/                      # VPC, IAM, S3, Secrets
│   ├── database/                     # RDS PostgreSQL
│   ├── cognito/                      # User Pool
│   ├── authorizer/                   # Lambda authorizer infrastructure
│   └── api-gateway/                  # REST API Gateway
├── apps/
│   ├── auth/
│   │   ├── src/                      # Lambda source code
│   │   └── deploy/                   # Terraform for Lambda
│   ├── authorizer/src/
│   └── job/
│       ├── src/
│       └── deploy/
├── nx                                # CLI deployment script
├── DEPLOYMENT_GUIDE.md               # This file
└── README.md                         # Project README
```

### Workflow Files

- **deploy-lambda.yml** - Deploys Lambda applications (auth, authorizer, job)
- **deploy-infrastructure.yml** - Deploys infrastructure modules (general, database, etc.)
- **test-integration.yml** - Runs integration tests on deployed environment

### Terraform State Structure

```
s3://rtr-tfstate/
├── general/dev/terraform.tfstate
├── general/ppe/terraform.tfstate
├── general/prod/terraform.tfstate
├── database/dev/terraform.tfstate
├── cognito/dev/terraform.tfstate
├── api-gateway/dev/terraform.tfstate
├── authorizer/dev/terraform.tfstate
├── auth/dev/terraform.tfstate
└── job/dev/terraform.tfstate
```
