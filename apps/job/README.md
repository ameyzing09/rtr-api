# RTR Job Lambda

Job management service Lambda function with full CRUD operations and multi-tenant isolation.

## Purpose

This Lambda function provides:
- Create, read, update, delete (CRUD) operations for jobs
- Multi-tenant data isolation using tenantId
- User-based authorization via Lambda authorizer
- Integration with PostgreSQL RDS database

## API Endpoints

| Method | Path | Description | Auth Required |
|--------|------|-------------|---------------|
| GET | /jobs | List all jobs for tenant | Yes |
| GET | /jobs/{id} | Get specific job | Yes |
| POST | /jobs | Create new job | Yes |
| PUT | /jobs/{id} | Update existing job | Yes |
| DELETE | /jobs/{id} | Delete job | Yes |

## Request/Response Examples

### List Jobs

**Request:**
```bash
GET /jobs
Authorization: Bearer eyJhbGc...
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "job-123",
      "title": "Backend Developer",
      "description": "Node.js developer needed",
      "status": "active",
      "createdAt": "2025-11-16T10:00:00Z",
      "updatedAt": "2025-11-16T10:00:00Z",
      "tenantId": "tenant-456"
    }
  ],
  "count": 1
}
```

### Create Job

**Request:**
```json
POST /jobs
Authorization: Bearer eyJhbGc...
Content-Type: application/json

{
  "title": "Frontend Developer",
  "description": "React developer with 3+ years experience",
  "status": "active",
  "requirements": {
    "experience": "3 years",
    "skills": ["React", "TypeScript", "CSS"]
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Job created successfully",
  "data": {
    "id": "job-124",
    "title": "Frontend Developer",
    "description": "React developer with 3+ years experience",
    "status": "active",
    "requirements": {
      "experience": "3 years",
      "skills": ["React", "TypeScript", "CSS"]
    },
    "createdAt": "2025-11-16T11:00:00Z",
    "updatedAt": "2025-11-16T11:00:00Z",
    "tenantId": "tenant-456",
    "createdBy": "user-123"
  }
}
```

### Update Job

**Request:**
```json
PUT /jobs/job-124
Authorization: Bearer eyJhbGc...
Content-Type: application/json

{
  "status": "closed",
  "description": "Position filled"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Job updated successfully",
  "data": {
    "id": "job-124",
    "title": "Frontend Developer",
    "description": "Position filled",
    "status": "closed",
    "updatedAt": "2025-11-16T12:00:00Z",
    "tenantId": "tenant-456"
  }
}
```

### Delete Job

**Request:**
```bash
DELETE /jobs/job-124
Authorization: Bearer eyJhbGc...
```

**Response:**
```json
{
  "success": true,
  "message": "Job deleted successfully"
}
```

## Multi-Tenant Isolation

All database queries include tenant filtering:

```javascript
// Automatic tenant filtering from JWT claims
const tenantId = event.requestContext?.authorizer?.tenantId;

// All queries include WHERE tenantId = ?
SELECT * FROM jobs WHERE tenantId = ? AND id = ?
INSERT INTO jobs (id, title, description, tenantId, ...) VALUES (?, ?, ?, ?, ...)
UPDATE jobs SET ... WHERE id = ? AND tenantId = ?
DELETE FROM jobs WHERE id = ? AND tenantId = ?
```

This ensures:
- Users can only access their tenant's data
- No cross-tenant data leakage
- Row-level security at application layer

## Local Development

### Prerequisites

- Node.js 18.x
- AWS CLI configured with credentials
- Terraform (for deployment)
- PostgreSQL 18.1+ (for local testing)

### Install Dependencies

```bash
cd src
npm install
```

### Environment Variables

Required (stored in AWS Secrets Manager for production):

- `DB_HOST` - RDS endpoint
- `DB_PORT` - Database port (default: 5432)
- `DB_NAME` - Database name
- `DB_USER` - Database username
- `DB_PASSWORD` - Database password
- `DB_SSL` - Use SSL for connection (default: true)

### Database Schema

```sql
CREATE TABLE jobs (
  id VARCHAR(255) PRIMARY KEY,
  tenantId VARCHAR(255) NOT NULL,
  title VARCHAR(500) NOT NULL,
  description TEXT,
  status VARCHAR(50) DEFAULT 'active',
  requirements JSONB,
  createdBy VARCHAR(255) NOT NULL,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_tenant (tenantId),
  INDEX idx_status (status),
  INDEX idx_created_at (createdAt)
);

-- Row-level security (optional - already enforced in application)
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON jobs
  USING (tenantId = current_setting('app.current_tenant')::VARCHAR);
```

### Test Locally

```bash
# Install dependencies
npm install

# Run tests (when implemented)
npm test

# Local invoke with mock event
node -e "require('./main').handler({
  httpMethod: 'GET',
  path: '/jobs',
  requestContext: {
    authorizer: {
      tenantId: 'test-tenant',
      userId: 'test-user'
    }
  }
}).then(console.log)"
```

## Deployment

### Option 1: Local Deployment (Immediate)

Deploy directly from your machine:

```bash
# Build and deploy to dev environment
./deploy-local.sh

# Or manually:
./build.sh
cd ../../apps/job/deploy/environments/dev
terraform init
terraform apply
```

### Option 2: GitHub Actions (CI/CD)

Automated deployment on code changes:

**Triggers:**
- Push to `main` branch with changes to `apps/job/**`
- Manual workflow dispatch with environment selection

**Required GitHub Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

**Manual Trigger:**
1. Go to Actions tab in GitHub
2. Select "Deploy Job Lambda"
3. Click "Run workflow"
4. Select environment (dev/ppe/prod)

## Infrastructure Dependencies

This Lambda requires:
- API Gateway with route `/jobs/*` configured
- Lambda Authorizer for JWT validation
- RDS PostgreSQL database
- VPC with private subnets for RDS access
- Security groups allowing Lambda → RDS traffic
- Secrets Manager for database credentials
- IAM role with permissions:
  - VPC network interface management
  - Secrets Manager read access
  - CloudWatch Logs write access
  - RDS connection permissions

## Error Responses

Standard error format:

```json
{
  "success": false,
  "message": "Job not found",
  "error": {
    "code": "NOT_FOUND",
    "details": "Job with ID job-999 does not exist"
  }
}
```

Common error codes:
- `NOT_FOUND` - Resource doesn't exist
- `VALIDATION_ERROR` - Invalid input data
- `UNAUTHORIZED` - Missing or invalid authorization
- `FORBIDDEN` - User doesn't have access to resource
- `DATABASE_ERROR` - Database operation failed

## Performance Considerations

- Connection pooling: Reuse database connections across invocations
- Caching: Consider caching frequently accessed jobs
- Pagination: Implement limit/offset for large result sets
- Indexes: Ensure tenantId, status, and createdAt are indexed

## Security Considerations

- All database queries use parameterized statements (prevent SQL injection)
- Tenant isolation enforced at query level
- Authorization context validated on every request
- Database credentials stored in Secrets Manager
- VPC isolation for database access
- TLS/SSL encryption for database connections

## Directory Structure

```
apps/job/
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

- [ ] Implement database connection pooling (using `pg-pool`)
- [ ] Add pagination support for list endpoints
- [ ] Implement search and filtering capabilities
- [ ] Add job status workflow (draft → active → closed → archived)
- [ ] Implement soft delete (mark as deleted instead of removing)
- [ ] Add audit trail (track all changes with timestamps and user)
- [ ] Implement bulk operations (create/update/delete multiple jobs)
- [ ] Add data validation using JSON Schema or Zod
- [ ] Implement caching layer (ElastiCache/Redis)
- [ ] Add full-text search capabilities
- [ ] Implement job versioning/history

## Notes

- Current implementation is a placeholder with mock responses
- Production version should use `pg` or `@aws-sdk/client-rds-data` for database access
- Consider implementing database migrations (Prisma, Knex, or raw SQL)
- Add comprehensive error handling and logging
- Implement request/response validation middleware
- Consider using ORM (Prisma, TypeORM, Sequelize) for complex queries
