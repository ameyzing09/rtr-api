# RTR Auth Lambda

Authentication service Lambda function that handles user login, federation, token refresh, and logout operations.

## Purpose

This Lambda function provides:
- User login with username/password
- Federated login (Google, Facebook, etc.)
- JWT token refresh
- User logout and session management
- Integration with AWS Cognito User Pool

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /auth/login | Authenticate user with credentials |
| POST | /auth/federate | Federated login (OAuth providers) |
| POST | /auth/refresh | Refresh access token |
| POST | /auth/logout | Logout and invalidate tokens |

## Request/Response Examples

### Login

**Request:**
```json
POST /auth/login
{
  "username": "user@example.com",
  "password": "SecurePassword123!"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "accessToken": "eyJhbGc...",
    "refreshToken": "eyJhbGc...",
    "expiresIn": 3600,
    "userId": "user-123",
    "tenantId": "tenant-456"
  }
}
```

### Refresh Token

**Request:**
```json
POST /auth/refresh
{
  "refreshToken": "eyJhbGc..."
}
```

**Response:**
```json
{
  "success": true,
  "message": "Token refreshed",
  "data": {
    "accessToken": "eyJhbGc...",
    "expiresIn": 3600
  }
}
```

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

### Environment Variables

Required for production (stored in AWS Secrets Manager):

- `COGNITO_USER_POOL_ID` - Cognito User Pool ID
- `COGNITO_CLIENT_ID` - Cognito App Client ID
- `COGNITO_CLIENT_SECRET` - Cognito App Client Secret (if configured)

### Test Locally

```bash
# Install dependencies
npm install

# Run tests (when implemented)
npm test

# Local invoke with SAM (optional)
sam local invoke -e event.json
```

## Deployment

### Option 1: Local Deployment (Immediate)

Deploy directly from your machine:

```bash
# Build and deploy to dev environment
./deploy-local.sh

# Or manually:
./build.sh
cd ../../apps/auth/deploy/environments/dev
terraform init
terraform apply
```

### Option 2: GitHub Actions (CI/CD)

Automated deployment on code changes:

**Triggers:**
- Push to `main` branch with changes to `apps/auth/**`
- Manual workflow dispatch with environment selection

**Required GitHub Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Manual Trigger:**
1. Go to Actions tab in GitHub
2. Select "Deploy Auth Lambda"
3. Click "Run workflow"
4. Select environment (dev/ppe/prod)

## Infrastructure Dependencies

This Lambda requires:
- API Gateway with route `/auth/*` configured
- Cognito User Pool for user authentication
- Secrets Manager for storing Cognito credentials
- IAM role with permissions:
  - Cognito user pool access
  - Secrets Manager read access
  - CloudWatch Logs write access

## Multi-Tenancy

The auth service handles tenant assignment:
- New users get assigned to default tenant or specified tenant during registration
- `tenantId` is stored as custom claim in Cognito user attributes
- All JWTs include `custom:tenantId` claim for downstream authorization

## Security Considerations

- All passwords must meet Cognito password policy
- Tokens expire after configured duration (default: 1 hour for access, 30 days for refresh)
- Failed login attempts trigger account lockout (Cognito managed)
- All endpoints use HTTPS only (enforced by API Gateway)

## Error Responses

Standard error format:

```json
{
  "success": false,
  "message": "Invalid credentials",
  "error": {
    "code": "INVALID_CREDENTIALS",
    "details": "Username or password is incorrect"
  }
}
```

## Directory Structure

```
apps/auth/
├── src/
│   ├── main.js           # Main handler
│   ├── package.json      # Dependencies
│   └── package-lock.json
├── deploy/
│   ├── resources/        # Terraform resources
│   └── environments/     # Environment configs
├── build.sh              # Build script
├── deploy-local.sh       # Local deployment
├── .gitignore
└── README.md
```

## Future Enhancements

- [ ] Add password reset functionality
- [ ] Implement email verification
- [ ] Add MFA support
- [ ] Implement account registration endpoint
- [ ] Add social login providers (Google, Facebook)
- [ ] Implement account deletion/deactivation
- [ ] Add rate limiting per user
- [ ] Implement session management API

## Notes

- Current implementation is a placeholder with mock responses
- Production version should use AWS Cognito SDK (`@aws-sdk/client-cognito-identity-provider`)
- Consider implementing request validation middleware
- Add comprehensive error handling and logging
