-- RTR API Database Schema
-- Supabase PostgreSQL Migration
-- Converted from MySQL migrations in:
--   - rtr-user-auth-service
--   - rtr-job-application-service
--   - rtr-pipeline-engine-service

------------------------------------------------------------
-- 1. TENANTS (multi-tenancy root)
------------------------------------------------------------
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL UNIQUE,
  domain VARCHAR(255) UNIQUE,
  slug VARCHAR(50) UNIQUE,
  plan TEXT CHECK (plan IN ('BASIC','STARTER','GROWTH','ENTERPRISE','ON_PREM')),
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','PROVISIONING','AWAITING_BRANDING','ACTIVE','FAILED','SUSPENDED','DELETED')),
  created_by UUID,
  failed_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_tenants_status ON tenants(status);
CREATE INDEX idx_tenants_plan ON tenants(plan);

------------------------------------------------------------
-- 2. JOBS (required for jobs Edge Function)
------------------------------------------------------------
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  location VARCHAR(255),
  department VARCHAR(255),
  extra JSONB,
  is_public BOOLEAN NOT NULL DEFAULT FALSE,
  publish_at TIMESTAMPTZ,
  expire_at TIMESTAMPTZ,
  external_apply_url VARCHAR(255),
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_tenant ON jobs(tenant_id);
CREATE INDEX idx_jobs_tenant_title ON jobs(tenant_id, title);
CREATE INDEX idx_jobs_public ON jobs(tenant_id, is_public, publish_at);

------------------------------------------------------------
-- 3. APPLICATIONS
------------------------------------------------------------
CREATE TABLE applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  applicant_name VARCHAR(255) NOT NULL,
  applicant_email VARCHAR(255) NOT NULL,
  applicant_phone VARCHAR(255),
  resume_url VARCHAR(255),
  cover_letter TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','REVIEWED','REJECTED','HIRED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_applications_tenant_status ON applications(tenant_id, status);
CREATE INDEX idx_applications_job ON applications(job_id);

------------------------------------------------------------
-- 4. USER PROFILES (linked to auth.users)
------------------------------------------------------------
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name VARCHAR(150) NOT NULL,
  role TEXT NOT NULL DEFAULT 'CANDIDATE'
    CHECK (role IN ('SUPERADMIN','ADMIN','HR','INTERVIEWER','VIEWER','CANDIDATE')),
  is_owner BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_user_profiles_tenant ON user_profiles(tenant_id);
CREATE INDEX idx_user_profiles_deleted_at ON user_profiles(deleted_at);

------------------------------------------------------------
-- 5. PIPELINES
------------------------------------------------------------
CREATE TABLE pipelines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  stages JSONB NOT NULL DEFAULT '[]',
  is_active BOOLEAN DEFAULT TRUE,
  is_deleted BOOLEAN DEFAULT FALSE,
  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, name)
);

CREATE INDEX idx_pipelines_tenant ON pipelines(tenant_id);
CREATE INDEX idx_pipelines_tenant_created_by ON pipelines(tenant_id, created_by);

------------------------------------------------------------
-- 6. PIPELINE ASSIGNMENTS
------------------------------------------------------------
CREATE TABLE pipeline_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  pipeline_id UUID NOT NULL REFERENCES pipelines(id) ON DELETE CASCADE,
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  assigned_by UUID,
  is_deleted BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, job_id)
);

CREATE INDEX idx_pipeline_assignments_tenant ON pipeline_assignments(tenant_id);
CREATE INDEX idx_pipeline_assignments_pipeline ON pipeline_assignments(pipeline_id);
CREATE INDEX idx_pipeline_assignments_job ON pipeline_assignments(job_id);

------------------------------------------------------------
-- 7. CANDIDATE STAGE PROGRESS
------------------------------------------------------------
CREATE TABLE candidate_stage_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
  pipeline_id UUID NOT NULL REFERENCES pipelines(id) ON DELETE CASCADE,
  current_stage VARCHAR(255) NOT NULL,
  stage_index INT NOT NULL,
  updated_by UUID,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_candidate_progress_app ON candidate_stage_progress(application_id);
CREATE INDEX idx_candidate_progress_stage ON candidate_stage_progress(stage_index);

------------------------------------------------------------
-- 8. STAGE FEEDBACK
------------------------------------------------------------
CREATE TABLE stage_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
  stage_name VARCHAR(255),
  given_by UUID,
  feedback TEXT,
  score FLOAT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_stage_feedback_app ON stage_feedback(application_id);

------------------------------------------------------------
-- 9. TENANT SETTINGS
------------------------------------------------------------
CREATE TABLE tenant_settings (
  tenant_id UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  config JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

------------------------------------------------------------
-- 10. SUBSCRIPTIONS
------------------------------------------------------------
CREATE TABLE subscriptions (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id UUID NOT NULL UNIQUE REFERENCES tenants(id) ON DELETE CASCADE,
  plan TEXT NOT NULL CHECK (plan IN ('BASIC','STARTER','GROWTH','ENTERPRISE','ON_PREM')),
  billing_cycle TEXT NOT NULL DEFAULT 'MONTHLY' CHECK (billing_cycle IN ('MONTHLY','ANNUAL')),
  status TEXT NOT NULL DEFAULT 'TRIAL' CHECK (status IN ('TRIAL','ACTIVE','GRACE','SUSPENDED','CANCELED')),
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  amount_cents INT NOT NULL DEFAULT 0,
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  trial_ends_at TIMESTAMPTZ,
  next_renewal_at TIMESTAMPTZ,
  canceled_at TIMESTAMPTZ,
  updated_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_status ON subscriptions(status);

------------------------------------------------------------
-- 11. AUDIT LOGS
------------------------------------------------------------
CREATE TABLE audit_logs (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  action VARCHAR(100) NOT NULL,
  actor_id UUID,
  actor_tenant_id UUID,
  actor_role VARCHAR(50),
  target_resource_id VARCHAR(255),
  target_resource_type VARCHAR(50),
  target_tenant_id UUID,
  status TEXT NOT NULL CHECK (status IN ('success','denied','error')),
  reason VARCHAR(255),
  ip_address VARCHAR(45),
  user_agent TEXT,
  metadata JSONB
);

CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_actor ON audit_logs(actor_id);
CREATE INDEX idx_audit_target_tenant ON audit_logs(target_tenant_id);
