# Application Lifecycle & Authority Model

## Entities

| Entity | Description |
|--------|-------------|
| **Job** | A published position that accepts applications |
| **Application** | A candidate's submission against a job |
| **Pipeline** | An ordered set of stages assigned to a job |
| **Stage** | A single step in a pipeline (e.g. "Phone Screen") |
| **Evaluation** | A scored assessment of an application within a stage |
| **Signal** | An evaluation outcome that feeds the decision gate (BLOCK / ALLOW / WARN) |
| **Action** | A side-effect triggered by a decision gate (e.g. advance, reject, notify) |

## Lifecycle Phases

```
1. Intake           Candidate submits application via public API or internal create.
2. Tracking Init    Jobs module calls tracking service to attach the application
                    to the job's pipeline. Tracking creates pipeline state.
3. Evaluation       Evaluation engine runs configured evaluations for the
                    current stage and produces signals.
4. Decision Gate    Signals are aggregated. Gate resolves to ADVANCE, HOLD, or REJECT.
5. Terminal         Application reaches a terminal state (HIRED / REJECTED / WITHDRAWN).
```

## Authority Table

| Decision | Owner | Notes |
|----------|-------|-------|
| Create / update / delete a job | **Jobs** | |
| Create an application | **Jobs** | Public + internal endpoints |
| Attach application to pipeline | **Jobs** (write-only call) | Fires POST to tracking; never reads tracking state |
| Pipeline state (current stage, is_terminal) | **Tracking** | Single source of truth |
| Advance / hold / reject an application | **Tracking** | Driven by decision gate output |
| Run evaluations for a stage | **Evaluations** | Triggered by tracking on stage entry |
| Produce signals from evaluations | **Evaluations** | |
| Execute side-effect actions | **Action Engine** | Consumes decision gate output |

> **Rule: Tracking state must never be read directly by the jobs module.**
> Jobs writes to tracking exactly once (attach on submit) and never queries
> `application_pipeline_state` or any tracking-owned table.

## Data Flow

```
                          +----------+
  Candidate / HR  ------->|   Jobs   |
                          +----+-----+
                               |
                     POST /tracking/.../attach  (write-only)
                               |
                               v
                          +----------+       +---------------+
                          | Tracking | ----->| Evaluations   |
                          +----+-----+       +-------+-------+
                               |                     |
                        reads/writes             produces
                     pipeline state              signals
                               |                     |
                               v                     v
                          +----------+       +---------------+
                          | Decision |<------| Signal Gate   |
                          |   Gate   |       +---------------+
                          +----+-----+
                               |
                               v
                        +-------------+
                        | Action      |
                        | Engine      |
                        +-------------+
```

## Signal Gate Model

Each evaluation produces a **signal** with one of three dispositions:

| Signal | Meaning | Gate Behaviour |
|--------|---------|----------------|
| **BLOCK** | Hard stop — application cannot advance | Gate resolves to REJECT (or HOLD if configured) |
| **ALLOW** | Evaluation passed | Gate advances if all required signals are ALLOW |
| **WARN** | Soft flag — does not block but surfaces to reviewers | Gate treats as ALLOW for advancement; flags in UI |

The gate evaluates signals only after **all required evaluations** for the current
stage have completed. If any required signal is BLOCK, the gate will not advance
the application regardless of other signals.

## Candidate Status Contract

### Token Policy

- Each public application receives a `candidate_access_token` (UUID).
- Tokens expire **30 days** after creation (`expires_at = NOW() + INTERVAL '30 days'`).
- Expiry is enforced both in the RPC (`get_application_by_token_v1`) and in the handler.
- Expired tokens return **410 Gone** with code `token_expired` — not a generic 404.
- Tokens are single-use per application (UNIQUE constraint on `application_id`).
- Tokens are **not renewable**. After expiry, the candidate must reapply or contact the recruiter.

### Terminal State Behaviour

- Once an application reaches a terminal state (HIRED / REJECTED / WITHDRAWN), its
  `application_pipeline_state` row is frozen by a database trigger.
- The status page **still returns data** for terminal applications (the candidate can
  see their final status). The status and stage simply stop changing.
- History does not mutate after terminal state is reached.

### Guaranteed Response Shape

`GET /public/applications/:token` always returns this exact shape. No optional fields.

```json
{
  "jobTitle":       "string",
  "status":         "string",
  "stageName":      "string",
  "appliedAt":      "ISO 8601 timestamp",
  "lastUpdatedAt":  "ISO 8601 timestamp"
}
```

When tracking state does not yet exist (race condition or pre-attach), the RPC
returns COALESCE defaults: `stageName = "Application Received"`, `status = "Pending"`.
