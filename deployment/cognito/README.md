# Cognito User Pool Infrastructure

AWS Cognito User Pool infrastructure for user authentication following the ConnectX pattern.

## Architecture

**ConnectX Pattern**: Single User Pool with custom `tenantId` attribute for multi-tenancy.

### Key Features

- **Free Tier Optimized**: 50,000 MAU (Monthly Active Users) free forever
- **Multi-Tenant Support**: Custom `tenantId` attribute for row-level isolation
- **OAuth 2.0**: Authorization code flow with refresh tokens
- **JWT Tokens**: Access, ID, and refresh tokens
- **MFA Support**: Software token (TOTP) available
- **Email Verification**: Auto-verify email addresses
- **Password Policy**: Configurable per environment
- **Advanced Security**: Compromised credentials detection (optional)

## Cost Breakdown

### Free Tier (First 50K MAU)
- **FREE** for first 50,000 Monthly Active Users
- Includes: Sign-up, sign-in, token refresh, password recovery
- Expires: **NEVER** (permanent free tier)

### Beyond Free Tier
- 50K-100K MAU: $0.00550 per MAU = $275/month
- 100K-1M MAU: $0.00460 per MAU
- 1M-10M MAU: $0.00325 per MAU
- 10M+ MAU: $0.00250 per MAU

### Advanced Security (Optional)
- Risk-based adaptive authentication
- Compromised credentials detection
- **Cost**: $0.05 per MAU (ENFORCED mode)
- **Free**: AUDIT mode logs but doesn't block

## Environment Configurations

### Dev
```hcl
mfa_configuration = "OFF"                 # Disabled for ease
password_minimum_length = 8               # Relaxed
email_sending_account = "COGNITO_DEFAULT" # Free 50 emails/day
advanced_security_mode = "OFF"            # Free tier
callback_urls = ["http://localhost:3000/callback"]
```

### PPE
```hcl
mfa_configuration = "OPTIONAL"            # Users can enable
password_minimum_length = 10              # Stricter
email_sending_account = "DEVELOPER"       # Use SES
advanced_security_mode = "AUDIT"          # Monitor only
callback_urls = ["https://rtr-ppe.com/callback"]
```

### Prod
```hcl
mfa_configuration = "ON"                  # REQUIRED
password_minimum_length = 12              # Strictest
email_sending_account = "DEVELOPER"       # Use SES
advanced_security_mode = "ENFORCED"       # Block threats
callback_urls = ["https://rtr.com/callback"]
```

## Directory Structure

```
deployment/cognito/
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
    ├── cognito.tf             # User Pool and App Client
    └── outputs.tf             # Output values
```

## Deployment

### Prerequisites

1. **AWS Credentials**: Configure AWS CLI
   ```bash
   aws configure
   ```

2. **S3 Backend**: Create Terraform state bucket
   ```bash
   aws s3 mb s3://rtr-terraform-state
   ```

3. **SES Email** (PPE/Prod): Verify sender email
   ```bash
   aws ses verify-email-identity --email-address noreply@rtr.com
   ```

### Deploy with Nx

```bash
# Dev environment
npx nx run cognito:plan:dev
npx nx run cognito:deploy:dev

# PPE environment
npx nx run cognito:deploy:ppe

# Production
npx nx run cognito:deploy:prod
```

### Manual Deployment

```bash
cd deployment/cognito/environments/dev
terraform init
terraform plan
terraform apply
```

## Configuration

### Custom Attributes

**tenantId**: Custom attribute for multi-tenant isolation
- Type: String
- Mutable: Yes
- Required: No (for flexibility)
- Max Length: 256 characters

### Token Validity

| Environment | Access Token | ID Token | Refresh Token |
|-------------|--------------|----------|---------------|
| Dev         | 60 min       | 60 min   | 30 days       |
| PPE         | 30 min       | 30 min   | 7 days        |
| Prod        | 15 min       | 15 min   | 1 day         |

### OAuth Flows

- **Dev**: `code`, `implicit` (for easier testing)
- **PPE/Prod**: `code` only (most secure)

## Usage from Apps

### Data Source Discovery (ConnectX Pattern)

```hcl
# In app deployment, reference Cognito resources
data "aws_cognito_user_pools" "main" {
  name = "rtr-${var.env}-users"
}

data "aws_secretsmanager_secret" "cognito_client" {
  name = "rtr-${var.env}-cognito-client-secret"
}
```

### Environment Variables for Lambda

```bash
USER_POOL_ID=ap-south-1_XXXXXXXXX
APP_CLIENT_ID=XXXXXXXXXXXXXXXXXXXXXXXXXX
AWS_REGION=ap-south-1
```

### JWT Token Claims

```json
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "custom:tenantId": "tenant-123",
  "cognito:username": "user@example.com",
  "email_verified": true
}
```

## Multi-Tenancy

### User Creation

```typescript
// When creating user, set tenantId attribute
await cognito.adminCreateUser({
  UserPoolId: userPoolId,
  Username: email,
  UserAttributes: [
    { Name: 'email', Value: email },
    { Name: 'custom:tenantId', Value: tenantId }
  ]
});
```

### Token Validation

```typescript
// Extract tenantId from JWT token
const decodedToken = jwt.decode(token);
const tenantId = decodedToken['custom:tenantId'];

// Use tenantId in database queries
const results = await db.query(
  'SELECT * FROM users WHERE tenantId = $1',
  [tenantId]
);
```

## Security Best Practices

1. **MFA**: Enable for production (required) and PPE (optional)
2. **Token Rotation**: Short-lived access tokens, longer refresh tokens
3. **Advanced Security**: Use AUDIT mode first, then ENFORCED
4. **Email Verification**: Always verify email before allowing sign-in
5. **Password Policy**: Increase requirements for production
6. **Deletion Protection**: ACTIVE for production

## Monitoring

### CloudWatch Metrics

- SignInSuccesses
- SignInFailures
- TokenRefreshSuccesses
- UserCreation
- PasswordResetRequests

### CloudWatch Logs

- `/aws/cognito/rtr-{env}-users`: Lambda trigger logs
- User authentication events
- Password reset attempts

## Troubleshooting

### Common Issues

1. **Email not verified**: Check SES verification status
   ```bash
   aws ses get-identity-verification-attributes --identities noreply@rtr.com
   ```

2. **Domain already exists**: Cognito domains are global
   - Use unique prefix: `rtr-{env}-{random}-auth`

3. **Token expired**: Check token validity settings
   - Access tokens expire quickly (15-60 min)
   - Use refresh tokens for long sessions

4. **Custom attribute not found**: Verify attribute name
   - Use `custom:tenantId` (with `custom:` prefix)

## Cost Optimization Tips

1. **Stay under 50K MAU**: Monitor active users monthly
2. **Use COGNITO_DEFAULT email**: Free for dev (50 emails/day)
3. **Disable Advanced Security in dev**: Saves $0.05/MAU
4. **Longer token validity in dev**: Reduces token refreshes
5. **Optional MFA in non-prod**: Reduces complexity

## Next Steps

1. **Deploy general infrastructure first** (VPC, IAM, S3)
2. **Deploy Cognito** (this module)
3. **Create Lambda authorizer** (in deployment/api-gateway/)
4. **Deploy apps** (auth, job, etc.)

## Resources

- [Cognito Pricing](https://aws.amazon.com/cognito/pricing/)
- [Cognito User Pool](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)
- [OAuth 2.0 Flows](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-authentication-flow.html)
- [JWT Tokens](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-with-identity-providers.html)
