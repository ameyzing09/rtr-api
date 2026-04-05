# Application Detail API

Single aggregated view of an application — candidate info, job details, pipeline tracking, interviews, evaluations, and a unified activity timeline.

**Service:** `application-detail`
**Base URL:** `{SUPABASE_URL}/functions/v1/application-detail`

---

## Table of Contents

1. [Authentication](#authentication)
2. [Endpoints](#endpoints)
3. [Response Schema](#response-schema)
4. [Role-Based Restrictions](#role-based-restrictions)
5. [Error Handling](#error-handling)
6. [TypeScript Interfaces](#typescript-interfaces)
7. [Examples](#examples)

---

## Authentication

### Step 1: Login

```http
POST {SUPABASE_URL}/functions/v1/auth/login
Content-Type: application/json
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

```json
{
  "email": "user@example.com",
  "password": "password"
}
```

**Response:**

```json
{
  "Token": "eyJhbGciOiJIUzI1NiIs...",
  "ExpiresAt": "2026-03-26T15:30:00.000Z",
  "User": {
    "ID": "895d2d2a-632f-4052-a7f8-619f1b82c8a7",
    "Email": "user@example.com",
    "Name": "Amey Kode",
    "TenantID": "b3bf1707-fbbf-4407-abb8-f5332ce12473",
    "Role": "ADMIN",
    "Permissions": ["job:*", "application:*", "pipeline:*", "interview:*"],
    "ForcePasswordReset": false
  },
  "TenantBranding": null
}
```

> **Note:** The login response uses **PascalCase** field names (this is the auth service convention).

### Step 2: Use the Token

Pass the `Token` value in the `Authorization` header on all subsequent requests.

**Required headers for every request:**

| Header          | Value                        | Required |
|-----------------|------------------------------|----------|
| `Authorization` | `Bearer {Token}`             | Yes      |
| `apikey`        | `{SUPABASE_PUBLISHABLE_KEY}` | Yes      |

**Optional headers:**

| Header        | Value    | Notes                                        |
|---------------|----------|----------------------------------------------|
| `X-Tenant-ID` | `{uuid}` | SUPERADMIN only — override tenant context    |
| `X-Request-ID`| `{string}`| Optional request tracing ID                 |

---

## Endpoints

### Health Check

```
GET /
```

- **Auth:** Not required
- **Response:** `200` plain text

```
rtr-application-detail-service: ok
```

---

### Get Application Detail

```
GET /applications/{applicationId}
```

Fetches the complete detail view for a single application.

**Path parameters:**

| Parameter       | Type | Description                          |
|-----------------|------|--------------------------------------|
| `applicationId` | UUID | The application to retrieve          |

**Query parameters:**

| Parameter        | Type    | Default | Range   | Description                    |
|------------------|---------|---------|---------|--------------------------------|
| `timeline_limit` | integer | `50`    | `1–200` | Max timeline entries to return |

**Allowed roles:** `SUPERADMIN`, `ADMIN`, `HR`, `INTERVIEWER`

> **INTERVIEWER** access requires the user to be assigned to at least one interview round for this application. Unassigned interviewers receive `403`.

---

## Response Schema

All successful responses are wrapped in a `data` envelope:

```json
{
  "data": {
    "viewerContext": { ... },
    "application": { ... },
    "candidate": { ... },
    "job": { ... },
    "tracking": { ... },
    "interviews": [ ... ],
    "evaluations": [ ... ],
    "timeline": [ ... ]
  }
}
```

### viewerContext

Metadata about the current viewer's permissions for this response.

| Field         | Type    | Description                                       |
|---------------|---------|---------------------------------------------------|
| `viewerRole`  | string  | Viewer's role: `SUPERADMIN`, `ADMIN`, `HR`, `INTERVIEWER` |
| `isRestricted`| boolean | `true` when role is `INTERVIEWER`                 |

**FE usage:** Use `isRestricted` to conditionally render/hide sensitive sections (resume, cover letter, full timeline).

---

### application

Core application record.

| Field         | Type           | Description                                      |
|---------------|----------------|--------------------------------------------------|
| `id`          | string (UUID)  | Application ID                                   |
| `status`      | string         | Application status (see below)                   |
| `createdAt`   | string (ISO 8601) | When the application was submitted            |
| `updatedAt`   | string (ISO 8601) | Last modification timestamp                   |
| `resumeUrl`   | string \| null | URL to resume file. **`null` if restricted.**    |
| `coverLetter` | string \| null | Cover letter text. **`null` if restricted.**     |

**Known status values:** `PENDING`, `IN_PROGRESS`, `HIRED`, `REJECTED`

---

### candidate

Applicant contact information.

| Field   | Type           | Description               |
|---------|----------------|---------------------------|
| `name`  | string         | Full name                 |
| `email` | string         | Email address             |
| `phone` | string \| null | Phone number (if provided)|

---

### job

Job posting details.

| Field        | Type           | Description         |
|--------------|----------------|---------------------|
| `id`         | string (UUID)  | Job ID              |
| `title`      | string         | Job title           |
| `department` | string \| null | Department name     |
| `location`   | string \| null | Office location     |

---

### tracking

Pipeline tracking state. **`null`** if the application has not been attached to a pipeline.

| Field               | Type              | Description                           |
|---------------------|-------------------|---------------------------------------|
| `pipelineId`        | string (UUID)     | Pipeline this application is in       |
| `currentStageId`    | string (UUID)     | Current stage ID                      |
| `currentStageName`  | string            | Human-readable stage name             |
| `currentStageIndex` | number            | 0-based position in the pipeline      |
| `status`            | string            | Tracking status (e.g. `IN_PROGRESS`, `HIRED`) |
| `outcomeType`       | string            | Outcome (e.g. `ADVANCED`, `SUCCESS`, `REJECTED`) |
| `isTerminal`        | boolean           | `true` if at a terminal stage         |
| `enteredStageAt`    | string (ISO 8601) | When the candidate entered this stage |

---

### interviews

Array of interview summaries. May be empty.

| Field             | Type              | Description                          |
|-------------------|-------------------|--------------------------------------|
| `id`              | string (UUID)     | Interview ID                         |
| `applicationId`   | string (UUID)     | Parent application                   |
| `pipelineStageId` | string (UUID)     | Pipeline stage where interview occurs|
| `stageName`       | string \| null    | Human-readable stage name            |
| `status`          | string            | `SCHEDULED`, `COMPLETED`, `CANCELLED`|
| `roundCount`      | number            | Total interview rounds               |
| `completedRounds` | number            | Rounds where all participants submitted |
| `interviewers`    | Interviewer[]     | Assigned interviewers (see below)    |
| `createdAt`       | string (ISO 8601) | When the interview was created       |

**Interviewer object:**

| Field      | Type           | Description             |
|------------|----------------|-------------------------|
| `userId`   | string (UUID)  | Interviewer's user ID   |
| `userName` | string \| null | Interviewer's name      |

---

### evaluations

Array of evaluation summaries. May be empty. **Filtered for INTERVIEWER** — see [Role-Based Restrictions](#role-based-restrictions).

| Field              | Type              | Description                              |
|--------------------|-------------------|------------------------------------------|
| `id`               | string (UUID)     | Evaluation instance ID                   |
| `applicationId`    | string (UUID)     | Parent application                       |
| `templateId`       | string (UUID)     | Evaluation template used                 |
| `templateName`     | string \| null    | Template name                            |
| `stageId`          | string \| null    | Pipeline stage (null for interview-level) |
| `stageName`        | string \| null    | Stage name (null for interview-level)    |
| `status`           | string            | `PENDING`, `IN_PROGRESS`, `COMPLETED`    |
| `participantCount` | number            | Total evaluators assigned                |
| `submittedCount`   | number            | Evaluators who have submitted            |
| `pendingCount`     | number            | `participantCount - submittedCount`      |
| `isInterviewLevel` | boolean           | `true` if tied to an interview round     |
| `createdAt`        | string (ISO 8601) | When the evaluation was created          |

---

### timeline

Activity timeline sorted **descending** by `timestamp` (newest first). Limited by `timeline_limit` query param (default 50, max 200).

| Field       | Type              | Description                            |
|-------------|-------------------|----------------------------------------|
| `type`      | string            | Event type (see table below)           |
| `timestamp` | string (ISO 8601) | When the event occurred                |
| `summary`   | string            | Human-readable one-line description    |
| `actorId`   | string \| null    | User who triggered the event           |
| `actorName` | string \| null    | Actor's display name                   |
| `metadata`  | object \| null    | Event-specific data (see table below)  |

**Event types and metadata:**

| type                     | summary example                            | metadata fields                                                                                    |
|--------------------------|--------------------------------------------|----------------------------------------------------------------------------------------------------|
| `APPLICATION_CREATED`    | `"Application submitted by Test User"`     | `null`                                                                                             |
| `STAGE_TRANSITION`       | `"Stage transition: MOVE"`                 | `{ fromStageId, fromStageName, toStageId, toStageName, action, reason }`                          |
| `INTERVIEW_CREATED`      | `"Interview created"`                      | `{ interviewId }`                                                                                  |
| `INTERVIEW_CANCELLED`    | `"Interview cancelled"`                    | `{ interviewId }`                                                                                  |
| `INTERVIEW_COMPLETED`    | `"Interview completed"`                    | `{ interviewId }`                                                                                  |
| `EVALUATION_SUBMITTED`   | `"Evaluation submitted"`                   | `{ evaluationId }`                                                                                 |
| `EVALUATION_COMPLETED`   | `"Evaluation completed"`                   | `{ evaluationId }`                                                                                 |

---

## Role-Based Restrictions

The `viewerContext.isRestricted` flag indicates whether field-level restrictions are applied.

| Data Section              | ADMIN / HR / SUPERADMIN       | INTERVIEWER (restricted)                         |
|---------------------------|-------------------------------|--------------------------------------------------|
| `application.resumeUrl`   | Actual value                  | Always `null`                                    |
| `application.coverLetter` | Actual value                  | Always `null`                                    |
| `evaluations`             | All evaluation instances      | Only instances where user is a participant       |
| `timeline`                | All event types               | Interview events only (see below)                |
| Access prerequisite       | Role check only               | Role check **+** must be assigned to application |

**Restricted timeline event types (INTERVIEWER only sees these):**
- `INTERVIEW_CREATED`
- `INTERVIEW_CANCELLED`
- `INTERVIEW_COMPLETED`

**Hidden from INTERVIEWER timeline:**
- `APPLICATION_CREATED`
- `STAGE_TRANSITION`
- `EVALUATION_SUBMITTED`
- `EVALUATION_COMPLETED`

### FE Implementation Guidance

```typescript
// Use viewerContext to conditionally render UI sections
if (data.viewerContext.isRestricted) {
  // Hide resume download button
  // Hide cover letter section
  // Show only interview-related timeline entries (already filtered by API)
  // Evaluations are already filtered to only those the user participates in
}
```

---

## Error Handling

All errors return a flat JSON object (not wrapped in `data`):

```json
{
  "code": "not_found",
  "message": "Application 550e8400-... not found",
  "status_code": 404
}
```

| HTTP Status | `code`             | When                                            |
|-------------|--------------------|-------------------------------------------------|
| `400`       | `validation_error` | Invalid UUID format or bad request              |
| `401`       | `unauthorized`     | Missing, invalid, or expired JWT                |
| `403`       | `forbidden`        | Role not allowed, or interviewer not assigned    |
| `404`       | `not_found`        | Application doesn't exist or wrong tenant       |

**Specific error messages:**

| Message                                        | Status | Scenario                            |
|------------------------------------------------|--------|-------------------------------------|
| `"Invalid application ID format"`              | 400    | Path param is not a valid UUID      |
| `"Unauthorized: Invalid or missing token"`     | 401    | No Bearer token or token expired    |
| `"Forbidden: Insufficient permissions"`        | 403    | Role is not in allowed list         |
| `"Forbidden: Not assigned to this application"`| 403    | INTERVIEWER not assigned to any round |
| `"Application {id} not found"`                 | 404    | No application with that ID in tenant |

### FE Error Handling

```typescript
try {
  const res = await fetch(`${BASE_URL}/applications/${id}`, { headers });
  if (!res.ok) {
    const error = await res.json();
    switch (error.code) {
      case 'unauthorized':
        // Redirect to login
        break;
      case 'forbidden':
        // Show "access denied" UI
        break;
      case 'not_found':
        // Show "application not found" UI
        break;
      case 'validation_error':
        // Show "invalid request" UI
        break;
    }
    return;
  }
  const { data } = await res.json();
  // Use data.viewerContext, data.application, etc.
} catch (err) {
  // Network error
}
```

---

## TypeScript Interfaces

Copy-pasteable interfaces for the FE codebase. All fields use **camelCase**.

```typescript
// ============================================
// Top-level response
// ============================================

interface ApplicationDetailApiResponse {
  data: ApplicationDetailData;
}

interface ApplicationDetailData {
  viewerContext: ViewerContext;
  application: Application;
  candidate: Candidate;
  job: Job;
  tracking: Tracking | null;
  interviews: InterviewSummary[];
  evaluations: EvaluationSummary[];
  timeline: TimelineEntry[];
}

// ============================================
// Sections
// ============================================

interface ViewerContext {
  viewerRole: 'SUPERADMIN' | 'ADMIN' | 'HR' | 'INTERVIEWER';
  isRestricted: boolean;
}

interface Application {
  id: string;
  status: string;
  createdAt: string;
  updatedAt: string;
  resumeUrl: string | null;
  coverLetter: string | null;
}

interface Candidate {
  name: string;
  email: string;
  phone: string | null;
}

interface Job {
  id: string;
  title: string;
  department: string | null;
  location: string | null;
}

interface Tracking {
  pipelineId: string;
  currentStageId: string;
  currentStageName: string;
  currentStageIndex: number;
  status: string;
  outcomeType: string;
  isTerminal: boolean;
  enteredStageAt: string;
}

interface InterviewSummary {
  id: string;
  applicationId: string;
  pipelineStageId: string;
  stageName: string | null;
  status: string;
  roundCount: number;
  completedRounds: number;
  interviewers: Interviewer[];
  createdAt: string;
}

interface Interviewer {
  userId: string;
  userName: string | null;
}

interface EvaluationSummary {
  id: string;
  applicationId: string;
  templateId: string;
  templateName: string | null;
  stageId: string | null;
  stageName: string | null;
  status: string;
  participantCount: number;
  submittedCount: number;
  pendingCount: number;
  isInterviewLevel: boolean;
  createdAt: string;
}

type TimelineEventType =
  | 'APPLICATION_CREATED'
  | 'STAGE_TRANSITION'
  | 'INTERVIEW_CREATED'
  | 'INTERVIEW_CANCELLED'
  | 'INTERVIEW_COMPLETED'
  | 'EVALUATION_SUBMITTED'
  | 'EVALUATION_COMPLETED';

interface TimelineEntry {
  type: TimelineEventType;
  timestamp: string;
  summary: string;
  actorId: string | null;
  actorName: string | null;
  metadata: StageTransitionMeta | InterviewMeta | EvaluationMeta | null;
}

// Timeline metadata variants
interface StageTransitionMeta {
  fromStageId: string | null;
  fromStageName: string | null;
  toStageId: string | null;
  toStageName: string | null;
  action: string;
  reason: string | null;
}

interface InterviewMeta {
  interviewId: string;
}

interface EvaluationMeta {
  evaluationId: string;
}

// ============================================
// Error response (not wrapped in data)
// ============================================

interface ApiError {
  code: 'validation_error' | 'unauthorized' | 'forbidden' | 'not_found';
  message: string;
  status_code: number;
  details?: string;
}
```

---

## Examples

### Full Payload (ADMIN)

**Request:**

```http
GET /functions/v1/application-detail/applications/4baa1f20-5bd1-4ecb-b572-b142cde53d7a
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

**Response: `200 OK`**

```json
{
  "data": {
    "viewerContext": {
      "viewerRole": "ADMIN",
      "isRestricted": false
    },
    "application": {
      "id": "4baa1f20-5bd1-4ecb-b572-b142cde53d7a",
      "status": "PENDING",
      "createdAt": "2026-01-17T15:20:02.832826+00:00",
      "updatedAt": "2026-01-17T15:20:02.832826+00:00",
      "resumeUrl": null,
      "coverLetter": null
    },
    "candidate": {
      "name": "Test User",
      "email": "test@example.com",
      "phone": null
    },
    "job": {
      "id": "fde8793a-b9c3-4639-9fcf-c0f29de98723",
      "title": "Software Engineer",
      "department": "Operations",
      "location": "Gurgaon"
    },
    "tracking": {
      "pipelineId": "00000000-0000-0000-0000-000000000100",
      "currentStageId": "e79a0797-fec4-4d0c-aa33-f1073e47e0d4",
      "currentStageName": "Phone Screen",
      "currentStageIndex": 1,
      "status": "HIRED",
      "outcomeType": "SUCCESS",
      "isTerminal": true,
      "enteredStageAt": "2026-01-17T15:22:57.368763+00:00"
    },
    "interviews": [
      {
        "id": "be67537c-f735-4b00-9613-f9343cc1db6b",
        "applicationId": "4baa1f20-5bd1-4ecb-b572-b142cde53d7a",
        "pipelineStageId": "9e235a3a-589b-488d-b884-39f64e4c7b49",
        "stageName": "Technical Interview",
        "status": "CANCELLED",
        "roundCount": 1,
        "completedRounds": 0,
        "interviewers": [
          {
            "userId": "19f9990d-8271-4698-83da-e6fbe9abd6e1",
            "userName": "Interviewer One"
          }
        ],
        "createdAt": "2026-02-12T16:26:50.870034+00:00"
      }
    ],
    "evaluations": [
      {
        "id": "61de1dda-47ea-46b1-bbdf-6b526c73155f",
        "applicationId": "4baa1f20-5bd1-4ecb-b572-b142cde53d7a",
        "templateId": "0502fa11-f4d5-40d8-a813-30813d9bb848",
        "templateName": "Default Interview Evaluation",
        "stageId": "9e235a3a-589b-488d-b884-39f64e4c7b49",
        "stageName": "Technical Interview",
        "status": "PENDING",
        "participantCount": 1,
        "submittedCount": 0,
        "pendingCount": 1,
        "isInterviewLevel": true,
        "createdAt": "2026-02-12T16:26:51.706035+00:00"
      }
    ],
    "timeline": [
      {
        "type": "INTERVIEW_CANCELLED",
        "timestamp": "2026-02-12T16:27:17.508065+00:00",
        "summary": "Interview cancelled",
        "actorId": null,
        "actorName": null,
        "metadata": {
          "interviewId": "be67537c-f735-4b00-9613-f9343cc1db6b"
        }
      },
      {
        "type": "INTERVIEW_CREATED",
        "timestamp": "2026-02-12T16:26:50.870034+00:00",
        "summary": "Interview created",
        "actorId": "895d2d2a-632f-4052-a7f8-619f1b82c8a7",
        "actorName": "Amey Kode",
        "metadata": {
          "interviewId": "be67537c-f735-4b00-9613-f9343cc1db6b"
        }
      },
      {
        "type": "STAGE_TRANSITION",
        "timestamp": "2026-01-17T15:24:10.671982+00:00",
        "summary": "Stage transition: HIRE",
        "actorId": null,
        "actorName": null,
        "metadata": {
          "fromStageId": "e79a0797-fec4-4d0c-aa33-f1073e47e0d4",
          "toStageId": "e79a0797-fec4-4d0c-aa33-f1073e47e0d4",
          "action": "HIRE",
          "reason": "Testing terminal status",
          "fromStageName": "Phone Screen",
          "toStageName": "Phone Screen"
        }
      },
      {
        "type": "STAGE_TRANSITION",
        "timestamp": "2026-01-17T15:22:57.368763+00:00",
        "summary": "Stage transition: MOVE",
        "actorId": null,
        "actorName": null,
        "metadata": {
          "fromStageId": "52a12536-6766-4feb-97cb-5113dfa967fc",
          "toStageId": "e79a0797-fec4-4d0c-aa33-f1073e47e0d4",
          "action": "MOVE",
          "reason": "Testing move stage",
          "fromStageName": "Applied",
          "toStageName": "Phone Screen"
        }
      },
      {
        "type": "STAGE_TRANSITION",
        "timestamp": "2026-01-17T15:20:08.636579+00:00",
        "summary": "Stage transition: MOVE",
        "actorId": null,
        "actorName": null,
        "metadata": {
          "fromStageId": null,
          "toStageId": "52a12536-6766-4feb-97cb-5113dfa967fc",
          "action": "MOVE",
          "reason": "Application attached to pipeline",
          "toStageName": "Applied"
        }
      },
      {
        "type": "APPLICATION_CREATED",
        "timestamp": "2026-01-17T15:20:02.832826+00:00",
        "summary": "Application submitted by Test User",
        "actorId": null,
        "actorName": "Test User",
        "metadata": null
      }
    ]
  }
}
```

---

### Restricted Payload (INTERVIEWER)

**Request:**

```http
GET /functions/v1/application-detail/applications/4baa1f20-5bd1-4ecb-b572-b142cde53d7a
Authorization: Bearer {INTERVIEWER_JWT}
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

**Response: `200 OK`**

Key differences from full payload:

```json
{
  "data": {
    "viewerContext": {
      "viewerRole": "INTERVIEWER",
      "isRestricted": true
    },
    "application": {
      "id": "4baa1f20-5bd1-4ecb-b572-b142cde53d7a",
      "status": "PENDING",
      "createdAt": "2026-01-17T15:20:02.832826+00:00",
      "updatedAt": "2026-01-17T15:20:02.832826+00:00",
      "resumeUrl": null,
      "coverLetter": null
    },
    "candidate": { "name": "Test User", "email": "test@example.com", "phone": null },
    "job": { "id": "fde8793a-...", "title": "Software Engineer", "department": "Operations", "location": "Gurgaon" },
    "tracking": { "...same as full..." },
    "interviews": [ "...same as full..." ],
    "evaluations": [
      "Only evaluations where this interviewer is a participant"
    ],
    "timeline": [
      {
        "type": "INTERVIEW_CANCELLED",
        "timestamp": "2026-02-12T16:27:17.508065+00:00",
        "summary": "Interview cancelled",
        "actorId": null,
        "actorName": null,
        "metadata": { "interviewId": "be67537c-f735-4b00-9613-f9343cc1db6b" }
      },
      {
        "type": "INTERVIEW_CREATED",
        "timestamp": "2026-02-12T16:26:50.870034+00:00",
        "summary": "Interview created",
        "actorId": "895d2d2a-632f-4052-a7f8-619f1b82c8a7",
        "actorName": "Amey Kode",
        "metadata": { "interviewId": "be67537c-f735-4b00-9613-f9343cc1db6b" }
      }
    ]
  }
}
```

> Notice: `resumeUrl` and `coverLetter` are `null`. Timeline only contains `INTERVIEW_*` events. `STAGE_TRANSITION` and `APPLICATION_CREATED` entries are excluded.

---

### Error: No Auth Token (401)

```http
GET /functions/v1/application-detail/applications/4baa1f20-5bd1-4ecb-b572-b142cde53d7a
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

```json
{
  "code": "unauthorized",
  "message": "Unauthorized: Invalid or missing token",
  "status_code": 401
}
```

---

### Error: Invalid UUID (400)

```http
GET /functions/v1/application-detail/applications/not-a-uuid
Authorization: Bearer {TOKEN}
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

```json
{
  "code": "validation_error",
  "message": "Invalid application ID format",
  "status_code": 400
}
```

---

### Error: Not Found (404)

```http
GET /functions/v1/application-detail/applications/00000000-0000-0000-0000-000000000000
Authorization: Bearer {TOKEN}
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

```json
{
  "code": "not_found",
  "message": "Application 00000000-0000-0000-0000-000000000000 not found",
  "status_code": 404
}
```

---

### Error: Unassigned Interviewer (403)

```http
GET /functions/v1/application-detail/applications/4baa1f20-5bd1-4ecb-b572-b142cde53d7a
Authorization: Bearer {UNASSIGNED_INTERVIEWER_JWT}
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

```json
{
  "code": "forbidden",
  "message": "Forbidden: Not assigned to this application",
  "status_code": 403
}
```

---

### Error: Wrong Role (403)

```http
GET /functions/v1/application-detail/applications/4baa1f20-5bd1-4ecb-b572-b142cde53d7a
Authorization: Bearer {CANDIDATE_JWT}
apikey: {SUPABASE_PUBLISHABLE_KEY}
```

```json
{
  "code": "forbidden",
  "message": "Forbidden: Insufficient permissions",
  "status_code": 403
}
```

---

## CORS

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type, x-tenant-id, x-request-id
Access-Control-Allow-Methods: GET, OPTIONS
```

Preflight `OPTIONS` requests return `200` with the above headers.
