# RTR Authorizer Lambda

Lambda authorizer function for API Gateway that validates JWT tokens and enforces multi-tenant access control.

## Purpose

This Lambda function:
- Validates JWT tokens from Cognito user pool
- Extracts user identity (userId, tenantId, email) from token claims
- Returns IAM policy allowing/denying API Gateway requests
- Passes user context to downstream Lambda functions

## JWT Claims Expected

The authorizer expects these claims in the JWT token:
- `sub` - User ID
- `custom:tenantId` - Tenant ID for multi-tenancy
- `email` - User email address

## Local Development

### Prerequisites

- Node.js 18.x
- AWS CLI configured with credentials
- Terraform (for deployment)

### Install Dependencies

```bash
cd src
npm install
```

### Test Locally

The authorizer expects this event format:

```json
{
  "type": "TOKEN",
  "authorizationToken": "Bearer eyJhbGc...",
  "methodArn": "arn:aws:execute-api:region:account:api/stage/method/path"
}
```

Or with API Gateway v2 format:

```json
{
  "headers": {
    "Authorization": "Bearer eyJhbGc..."
  },
  "methodArn": "arn:aws:execute-api:region:account:api/stage/method/path"
}
```

## Deployment

### Option 1: Local Deployment (Immediate)

Deploy directly from your machine:

```bash
# Build and deploy to dev environment
./deploy-local.sh

# Or manually:
./build.sh
cd ../../deployment/authorizer/environments/dev
terraform init
terraform apply
```

### Option 2: GitHub Actions (CI/CD)

Automated deployment on code changes:

**Triggers:**
- Push to `main` branch with changes to `apps/authorizer/**`
- Manual workflow dispatch with environment selection

**Required GitHub Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Manual Trigger:**
1. Go to Actions tab in GitHub
2. Select "Deploy Authorizer Lambda"
3. Click "Run workflow"
4. Select environment (dev/ppe/prod)

## Environment Variables

No environment variables required. The authorizer uses:
- JWT token validation (basic format check)
- Claim extraction from token payload

## Infrastructure Dependencies

This Lambda requires:
- Cognito User Pool (for JWT token issuance)
- API Gateway (configured to use this authorizer)
- IAM role with Lambda execution permissions

## Response Format

Returns IAM policy document:

```json
{
  "principalId": "userId",
  "policyDocument": {
    "Version": "2012-10-17",
    "Statement": [{
      "Action": "execute-api:Invoke",
      "Effect": "Allow",
      "Resource": "methodArn"
    }]
  },
  "context": {
    "userId": "user-123",
    "tenantId": "tenant-456",
    "email": "user@example.com"
  }
}
```

## Directory Structure

```
apps/authorizer/
├── src/
│   ├── index.js          # Main handler
│   ├── package.json      # Dependencies
│   └── package-lock.json
├── build.sh              # Build script
├── deploy-local.sh       # Local deployment
├── .gitignore
└── README.md
```

## Notes

- Current implementation does basic JWT format validation
- For production, integrate with AWS Secrets Manager to fetch Cognito JWKS
- Add proper JWT signature verification using `jsonwebtoken` or `aws-jwt-verify`
- Consider caching authorization decisions for better performance
