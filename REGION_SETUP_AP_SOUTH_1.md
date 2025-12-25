# AWS Region: ap-south-1 (Asia Pacific - Mumbai)

## ✅ Region Updated

All infrastructure has been configured to use **ap-south-1** (Mumbai, India) instead of us-east-1.

### Why ap-south-1?

✅ **Lower Latency**: Local to India/South Asia
✅ **Better Reliability**: Avoids US server outages
✅ **Data Residency**: Data stays in India (compliance)
✅ **Cost Effective**: Competitive pricing

---

## 🌍 Region Information

**Region Code**: `ap-south-1`
**Location**: Mumbai, India
**Availability Zones**: 3 AZs (ap-south-1a, ap-south-1b, ap-south-1c)
**Launch Year**: 2016

### Availability Zones Used

Your infrastructure uses 2 AZs for high availability:
- **ap-south-1a**: Public subnet, Private subnet, Database subnet
- **ap-south-1b**: Public subnet, Private subnet, Database subnet

---

## 💰 Pricing Comparison (ap-south-1 vs us-east-1)

| Service | ap-south-1 | us-east-1 | Difference |
|---------|-----------|-----------|------------|
| **RDS db.t3.micro** | $0.018/hr | $0.017/hr | +6% |
| **Lambda (per 1M requests)** | $0.20 | $0.20 | Same |
| **API Gateway REST** | $3.50/M | $3.50/M | Same |
| **S3 Storage** | $0.025/GB | $0.023/GB | +9% |
| **NAT Gateway** | $0.048/hr | $0.045/hr | +7% |
| **Data Transfer OUT** | $0.109/GB | $0.09/GB | +21% |

**Total Monthly Cost**: ~$20/month (vs $19 in us-east-1)
**Difference**: +$1/month (~5% more)

**Free Tier**: Same as us-east-1 (12 months free for most services)

---

## 🔧 AWS CLI Configuration

Configure AWS CLI for ap-south-1:

```bash
aws configure
```

**Enter these values**:
```
AWS Access Key ID [None]: YOUR_ACCESS_KEY
AWS Secret Access Key [None]: YOUR_SECRET_KEY
Default region name [None]: ap-south-1
Default output format [None]: json
```

### Verify Region

```bash
# Check current region
aws configure get region
# Output: ap-south-1

# Test connectivity to ap-south-1
aws ec2 describe-regions --region ap-south-1

# List availability zones
aws ec2 describe-availability-zones --region ap-south-1
# Output:
# ap-south-1a
# ap-south-1b
# ap-south-1c
```

---

## ✅ Services Available in ap-south-1

All services used by RTR API are available in ap-south-1:

✅ **Compute**:
- Lambda
- EC2

✅ **Database**:
- RDS PostgreSQL
- DynamoDB

✅ **Networking**:
- VPC
- NAT Gateway
- Elastic IP
- Route53

✅ **Security**:
- IAM
- Cognito
- Secrets Manager
- Certificate Manager (ACM)

✅ **Application Integration**:
- API Gateway (REST & HTTP)
- SQS
- SNS
- EventBridge

✅ **Storage**:
- S3

✅ **Monitoring**:
- CloudWatch
- X-Ray

✅ **Developer Tools**:
- CodePipeline
- CodeBuild
- CodeDeploy

---

## 🚀 Deployment with ap-south-1

### 1. AWS CLI Setup

```bash
# Configure for ap-south-1
aws configure set region ap-south-1

# Verify
aws sts get-caller-identity
```

### 2. Update Terraform Variables

✅ **Already done!** All files updated to ap-south-1:

- ✅ Terraform backend configs (`region = "ap-south-1"`)
- ✅ Provider configs (`aws_region = "ap-south-1"`)
- ✅ Environment configs (all dev/ppe/prod)
- ✅ GitHub Actions workflows
- ✅ Documentation

### 3. Deploy Infrastructure

```bash
# 1. Create Terraform state bucket
cd deployment/firstRunCreateBucket/dev
terraform init
terraform apply
# Creates bucket in ap-south-1

# 2. Deploy core infrastructure
cd deployment/general/environments/dev
terraform init -backend-config="region=ap-south-1"
terraform apply
# All resources created in ap-south-1

# 3. Continue with other modules
cd deployment/database/environments/dev && terraform apply
cd deployment/cognito/environments/dev && terraform apply
cd deployment/authorizer/environments/dev && terraform apply
cd deployment/api-gateway/environments/dev && terraform apply

# 4. Deploy apps
cd apps/auth/deploy/environments/dev && terraform apply
cd apps/job/deploy/environments/dev && terraform apply
```

---

## 🌐 Endpoint URLs

After deployment, your endpoints will be:

```
API Gateway: https://XXXXXXXXXX.execute-api.ap-south-1.amazonaws.com/dev
RDS Endpoint: rtr-dev-db.XXXXXXXXXX.ap-south-1.rds.amazonaws.com
S3 Bucket: rtr-terraform-state (in ap-south-1)
```

Example:
```bash
# Get API endpoint
cd apps/auth/deploy/environments/dev
terraform output login_endpoint

# Output:
# https://abc123xyz.execute-api.ap-south-1.amazonaws.com/dev/auth/login
```

---

## 🔒 Data Residency & Compliance

### Data Location

All data stays in **Mumbai, India**:
- ✅ RDS PostgreSQL database
- ✅ S3 buckets (Terraform state, artifacts)
- ✅ CloudWatch logs
- ✅ Secrets Manager (JWT keys, DB credentials)
- ✅ Cognito User Pool data

### Compliance

**India Data Residency**: Suitable for:
- Indian companies requiring local data storage
- GDPR compliance (adequate data protection)
- Banking/Finance regulations (RBI guidelines)

**Cross-Border Data Transfer**:
- No automatic data transfer to US
- Full control over data location
- Compliant with data localization requirements

---

## 📊 Performance

### Latency from India

| Location | Latency to ap-south-1 | Latency to us-east-1 |
|----------|----------------------|---------------------|
| Mumbai | 1-5 ms | 250-300 ms |
| Delhi | 15-25 ms | 250-300 ms |
| Bangalore | 10-20 ms | 250-300 ms |
| Hyderabad | 8-18 ms | 250-300 ms |
| Singapore | 40-60 ms | 230-280 ms |

**Improvement**: ~240ms faster response times for Indian users! 🚀

### Throughput

- **Same as us-east-1**: No difference
- **API Gateway**: Up to 10,000 RPS per API
- **Lambda**: Up to 1,000 concurrent executions (can increase)
- **RDS**: Same performance characteristics

---

## 🚨 Troubleshooting

### "Service not available in ap-south-1"

**All RTR API services ARE available in ap-south-1**. If you see this error:

```bash
# Check service availability
aws service-quotas list-services --region ap-south-1 | grep -i "service-name"
```

### "Insufficient capacity"

Rare in ap-south-1, but if you encounter:

```bash
# Try different instance type
# RDS: db.t3.micro → db.t4g.micro (ARM-based, cheaper)
# Lambda: Same (serverless, no capacity issues)
```

### "Invalid availability zone"

Use only these AZs:
- ✅ `ap-south-1a`
- ✅ `ap-south-1b`
- ✅ `ap-south-1c`

❌ NOT: `ap-south-1d`, `ap-south-1e`

---

## 🔄 Migrating from us-east-1 (If Needed)

If you already deployed to us-east-1 and want to migrate:

### Option 1: Fresh Deployment (Recommended)

```bash
# 1. Destroy us-east-1 resources
cd deployment/general/environments/dev
terraform destroy

# 2. Update region (already done)
# 3. Deploy to ap-south-1
terraform apply
```

### Option 2: Data Migration

```bash
# 1. Export RDS data from us-east-1
aws rds create-db-snapshot --region us-east-1 \
  --db-instance-identifier rtr-dev-db \
  --db-snapshot-identifier rtr-dev-snapshot

# 2. Copy snapshot to ap-south-1
aws rds copy-db-snapshot --region ap-south-1 \
  --source-db-snapshot-identifier arn:aws:rds:us-east-1:ACCOUNT:snapshot:rtr-dev-snapshot \
  --target-db-snapshot-identifier rtr-dev-snapshot-ap-south-1

# 3. Restore in ap-south-1
aws rds restore-db-instance-from-db-snapshot --region ap-south-1 \
  --db-instance-identifier rtr-dev-db \
  --db-snapshot-identifier rtr-dev-snapshot-ap-south-1
```

---

## 📚 Resources

- [AWS ap-south-1 Region](https://aws.amazon.com/about-aws/global-infrastructure/regions_az/)
- [India Data Residency](https://aws.amazon.com/compliance/data-privacy-faq/)
- [ap-south-1 Services](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/)
- [Pricing ap-south-1](https://aws.amazon.com/pricing/)

---

## ✅ Summary

**Region**: ap-south-1 (Mumbai, India)
**Status**: ✅ All infrastructure updated
**Cost Impact**: +$1/month (~5% more than us-east-1)
**Latency**: 240ms faster for India users
**Data Residency**: India
**Availability**: All services available

**Ready to deploy!** 🇮🇳🚀
