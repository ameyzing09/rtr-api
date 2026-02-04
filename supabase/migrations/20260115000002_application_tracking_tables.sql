-- Application Tracking Service Tables
-- Separates PROCESS (tracking) from INTAKE (job-application)

-- ============================================
-- 0. PIPELINE STAGES TABLE (Denormalized from JSONB)
-- ============================================
-- Provides UUID-based stage references for tracking integrity
-- Stages are still defined in pipelines.stages JSONB, but this table
-- provides stable IDs for tracking and history

CREATE TABLE pipeline_stages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,  -- NULL for global pipelines
  pipeline_id UUID NOT NULL REFERENCES pipelines(id) ON DELETE CASCADE,
  stage_name VARCHAR(255) NOT NULL,
  stage_type VARCHAR(50) NOT NULL,
  conducted_by VARCHAR(50) NOT NULL,
  order_index INT NOT NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(pipeline_id, order_index)
);

CREATE INDEX idx_pipeline_stages_pipeline ON pipeline_stages(pipeline_id);
CREATE INDEX idx_pipeline_stages_order ON pipeline_stages(pipeline_id, order_index);

-- ============================================
-- 1. APPLICATION PIPELINE STATE TABLE
-- ============================================
-- Tracks where an application is in its hiring pipeline

CREATE TABLE application_pipeline_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id),
  application_id UUID UNIQUE NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
  job_id UUID NOT NULL REFERENCES jobs(id),
  pipeline_id UUID NOT NULL REFERENCES pipelines(id),
  current_stage_id UUID NOT NULL REFERENCES pipeline_stages(id),
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'HIRED', 'REJECTED', 'WITHDRAWN', 'ON_HOLD')),
  entered_stage_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX idx_app_pipeline_state_tenant ON application_pipeline_state(tenant_id);
CREATE INDEX idx_app_pipeline_state_pipeline ON application_pipeline_state(pipeline_id);
CREATE INDEX idx_app_pipeline_state_stage ON application_pipeline_state(current_stage_id);
CREATE INDEX idx_app_pipeline_state_status ON application_pipeline_state(tenant_id, status);
CREATE INDEX idx_app_pipeline_state_job ON application_pipeline_state(job_id);

-- ============================================
-- 2. APPLICATION STAGE HISTORY TABLE
-- ============================================
-- Audit trail for all stage transitions and status changes

CREATE TABLE application_stage_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id),
  application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
  pipeline_id UUID NOT NULL REFERENCES pipelines(id),
  from_stage_id UUID REFERENCES pipeline_stages(id),
  to_stage_id UUID REFERENCES pipeline_stages(id),
  action TEXT NOT NULL CHECK (action IN ('MOVE', 'REJECT', 'HIRE', 'WITHDRAW', 'HOLD', 'ACTIVATE')),
  changed_by UUID REFERENCES auth.users(id),
  changed_at TIMESTAMPTZ DEFAULT NOW(),
  reason TEXT
);

-- Indexes for audit queries
CREATE INDEX idx_app_stage_history_app ON application_stage_history(application_id);
CREATE INDEX idx_app_stage_history_tenant ON application_stage_history(tenant_id);
CREATE INDEX idx_app_stage_history_changed_at ON application_stage_history(changed_at DESC);

-- ============================================
-- 3. ENABLE RLS
-- ============================================

ALTER TABLE application_pipeline_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE application_stage_history ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 4. RLS POLICIES - application_pipeline_state
-- ============================================

-- SUPERADMIN: full access
CREATE POLICY "superadmin_full_access_pipeline_state" ON application_pipeline_state
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR: tenant-scoped access
CREATE POLICY "managers_manage_pipeline_state" ON application_pipeline_state
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_applications()
  );

-- INTERVIEWER: read-only access to tenant applications
CREATE POLICY "interviewers_view_pipeline_state" ON application_pipeline_state
  FOR SELECT USING (
    public.get_user_role() = 'INTERVIEWER'
    AND tenant_id = public.get_tenant_id()
  );

-- ============================================
-- 5. RLS POLICIES - application_stage_history
-- ============================================

-- SUPERADMIN: full access
CREATE POLICY "superadmin_full_access_stage_history" ON application_stage_history
  FOR ALL USING (public.is_superadmin());

-- ADMIN/HR: tenant-scoped access
CREATE POLICY "managers_manage_stage_history" ON application_stage_history
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_applications()
  );

-- INTERVIEWER: read-only access to tenant history
CREATE POLICY "interviewers_view_stage_history" ON application_stage_history
  FOR SELECT USING (
    public.get_user_role() = 'INTERVIEWER'
    AND tenant_id = public.get_tenant_id()
  );

-- ============================================
-- 6. UPDATED_AT TRIGGER
-- ============================================

CREATE TRIGGER update_app_pipeline_state_updated_at
  BEFORE UPDATE ON application_pipeline_state
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- 7. RLS FOR PIPELINE_STAGES
-- ============================================

ALTER TABLE pipeline_stages ENABLE ROW LEVEL SECURITY;

-- SUPERADMIN: full access
CREATE POLICY "superadmin_full_access_pipeline_stages" ON pipeline_stages
  FOR ALL USING (public.is_superadmin());

-- All authenticated users can view stages (needed for tracking)
CREATE POLICY "authenticated_view_pipeline_stages" ON pipeline_stages
  FOR SELECT USING (
    tenant_id IS NULL  -- Global pipelines
    OR tenant_id = public.get_tenant_id()
  );

-- Only managers can modify stages
CREATE POLICY "managers_manage_pipeline_stages" ON pipeline_stages
  FOR ALL USING (
    NOT public.is_superadmin()
    AND (tenant_id IS NULL OR tenant_id = public.get_tenant_id())
    AND public.can_manage_applications()
  );

-- ============================================
-- 8. SYNC FUNCTION: POPULATE PIPELINE_STAGES FROM JSONB
-- ============================================
-- This function extracts stages from pipelines.stages JSONB
-- and inserts them into pipeline_stages table with stable UUIDs

CREATE OR REPLACE FUNCTION sync_pipeline_stages()
RETURNS TRIGGER AS $$
BEGIN
  -- Delete existing stages for this pipeline
  DELETE FROM pipeline_stages WHERE pipeline_id = NEW.id;

  -- Insert stages from JSONB array
  INSERT INTO pipeline_stages (
    tenant_id,
    pipeline_id,
    stage_name,
    stage_type,
    conducted_by,
    order_index,
    metadata
  )
  SELECT
    NEW.tenant_id,
    NEW.id,
    (stage->>'stage')::VARCHAR(255),
    (stage->>'type')::VARCHAR(50),
    (stage->>'conducted_by')::VARCHAR(50),
    (ordinality - 1)::INT,  -- 0-indexed
    stage->'metadata'
  FROM jsonb_array_elements(COALESCE(NEW.stages, '[]'::jsonb)) WITH ORDINALITY AS t(stage, ordinality);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to sync stages on pipeline create/update
CREATE TRIGGER sync_pipeline_stages_trigger
  AFTER INSERT OR UPDATE OF stages ON pipelines
  FOR EACH ROW
  EXECUTE FUNCTION sync_pipeline_stages();

-- ============================================
-- 9. BACKFILL EXISTING PIPELINES
-- ============================================
-- Populate pipeline_stages for all existing pipelines

INSERT INTO pipeline_stages (
  tenant_id,
  pipeline_id,
  stage_name,
  stage_type,
  conducted_by,
  order_index,
  metadata
)
SELECT
  p.tenant_id,
  p.id,
  (stage->>'stage')::VARCHAR(255),
  (stage->>'type')::VARCHAR(50),
  (stage->>'conducted_by')::VARCHAR(50),
  (ordinality - 1)::INT,
  stage->'metadata'
FROM pipelines p
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.stages, '[]'::jsonb)) WITH ORDINALITY AS t(stage, ordinality)
WHERE p.is_deleted = false;

-- ============================================
-- 10. DROP OLD TABLE (candidate_stage_progress)
-- ============================================
-- The old table used string-based stage tracking
-- New table uses UUID references for integrity

DROP TABLE IF EXISTS candidate_stage_progress CASCADE;
