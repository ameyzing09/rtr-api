-- ============================================================================
-- Migration: Stage Evaluations — auto-creation on stage entry
-- ============================================================================
-- Adds:
--   1. stage_evaluations table (template-per-stage config)
--   2. ensure_stage_evaluations() callable function
--   3. Safety-net trigger on application_pipeline_state
--   4. UNIQUE constraint on evaluation_instances for idempotency
--   5. RLS policies (SELECT for HR+, INSERT/UPDATE for ADMIN+, no DELETE)
--   6. Seed function + trigger for system default stages
-- ============================================================================

-- ============================================================================
-- PART 1: stage_evaluations table
-- ============================================================================

CREATE TABLE stage_evaluations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  stage_id UUID NOT NULL REFERENCES pipeline_stages(id) ON DELETE CASCADE,
  evaluation_template_id UUID NOT NULL REFERENCES evaluation_templates(id) ON DELETE RESTRICT,
  execution_order INT NOT NULL DEFAULT 1,
  auto_create BOOLEAN DEFAULT true,
  required BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, stage_id, execution_order, evaluation_template_id)
);

CREATE INDEX idx_stage_evaluations_tenant ON stage_evaluations(tenant_id);
CREATE INDEX idx_stage_evaluations_stage ON stage_evaluations(stage_id);
CREATE INDEX idx_stage_evaluations_template ON stage_evaluations(evaluation_template_id);
CREATE INDEX idx_stage_evaluations_lookup ON stage_evaluations(stage_id, auto_create, is_active);

COMMENT ON TABLE stage_evaluations IS
  'Maps evaluation templates to pipeline stages for auto-creation when applications enter a stage';

-- ============================================================================
-- PART 2: Unique constraint on evaluation_instances for idempotency
-- ============================================================================

ALTER TABLE evaluation_instances
  ADD CONSTRAINT uq_evaluation_instances_app_template_stage
  UNIQUE (tenant_id, application_id, template_id, stage_id);

-- ============================================================================
-- PART 3: ensure_stage_evaluations() — callable function
-- ============================================================================

CREATE OR REPLACE FUNCTION ensure_stage_evaluations(
  p_tenant_id UUID,
  p_application_id UUID,
  p_stage_id UUID
) RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INT := 0;
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT se.evaluation_template_id, se.execution_order
    FROM stage_evaluations se
    WHERE se.stage_id = p_stage_id
      AND se.auto_create = true
      AND se.is_active = true
    ORDER BY se.execution_order
  LOOP
    INSERT INTO evaluation_instances (
      tenant_id, application_id, template_id, stage_id, status
    ) VALUES (
      p_tenant_id, p_application_id, v_rec.evaluation_template_id, p_stage_id, 'PENDING'
    )
    ON CONFLICT (tenant_id, application_id, template_id, stage_id) DO NOTHING;

    IF FOUND THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RAISE LOG 'STAGE_EVAL_AUTO_CREATE: app=% stage=% created=%', p_application_id, p_stage_id, v_count;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION ensure_stage_evaluations IS
  'Auto-creates evaluation instances for an application entering a stage. Idempotent via ON CONFLICT.';

-- ============================================================================
-- PART 4: Update attach_application_to_pipeline_v1 — call ensure_stage_evaluations
-- ============================================================================

CREATE OR REPLACE FUNCTION attach_application_to_pipeline_v1(
  p_tenant_id UUID,
  p_application_id UUID,
  p_job_id UUID,
  p_pipeline_id UUID,
  p_first_stage_id UUID,
  p_user_id UUID DEFAULT NULL
) RETURNS tracking_state_result
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_state application_pipeline_state;
  v_result tracking_state_result;
  v_event_hash TEXT;
BEGIN
  -- SECURITY: Verify application belongs to tenant (don't trust caller)
  IF NOT EXISTS (
    SELECT 1 FROM applications
    WHERE id = p_application_id AND tenant_id = p_tenant_id
  ) THEN
    RAISE EXCEPTION 'TENANT_MISMATCH: Application does not belong to tenant'
      USING ERRCODE = 'P0002';
  END IF;

  -- SECURITY: Verify job belongs to tenant
  IF NOT EXISTS (
    SELECT 1 FROM jobs
    WHERE id = p_job_id AND tenant_id = p_tenant_id
  ) THEN
    RAISE EXCEPTION 'TENANT_MISMATCH: Job does not belong to tenant'
      USING ERRCODE = 'P0002';
  END IF;

  -- SECURITY: Verify stage belongs to pipeline
  IF NOT EXISTS (
    SELECT 1 FROM pipeline_stages
    WHERE id = p_first_stage_id AND pipeline_id = p_pipeline_id
  ) THEN
    RAISE EXCEPTION 'INVALID_STAGE: Stage does not belong to pipeline'
      USING ERRCODE = 'P0003';
  END IF;

  -- Insert state (UNIQUE on application_id handles duplicate attach -> 23505)
  INSERT INTO application_pipeline_state (
    tenant_id, application_id, job_id, pipeline_id,
    current_stage_id, status, entered_stage_at
  ) VALUES (
    p_tenant_id, p_application_id, p_job_id, p_pipeline_id,
    p_first_stage_id, 'ACTIVE', NOW()
  )
  RETURNING * INTO v_state;

  -- Compute event hash for idempotency
  v_event_hash := md5(p_application_id::text || 'MOVE' || 'null' || p_first_stage_id::text);

  -- Insert history with ON CONFLICT for idempotency (no duplicate history)
  INSERT INTO application_stage_history (
    tenant_id, application_id, pipeline_id,
    from_stage_id, to_stage_id, action, changed_by, reason, event_hash
  ) VALUES (
    p_tenant_id, p_application_id, p_pipeline_id,
    NULL, p_first_stage_id, 'MOVE', p_user_id, 'Application attached to pipeline', v_event_hash
  )
  ON CONFLICT (event_hash) WHERE event_hash IS NOT NULL DO NOTHING;

  -- Auto-create stage evaluations for the first stage
  PERFORM ensure_stage_evaluations(p_tenant_id, p_application_id, p_first_stage_id);

  -- Log for observability
  RAISE LOG 'TRACKING_ATTACH: app=% tenant=% pipeline=%', p_application_id, p_tenant_id, p_pipeline_id;

  -- Return decoupled DTO (not raw table row)
  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
  RETURN v_result;
END;
$$;

-- ============================================================================
-- PART 5: Update execute_action_v2 — call ensure_stage_evaluations on stage change
-- ============================================================================
-- We add a PERFORM ensure_stage_evaluations() call after the stage mutation
-- when the stage actually changed. We do this by reading the full current
-- function and re-creating it with the addition.
-- Instead of duplicating the entire 400+ line function, we use a wrapper
-- approach via a trigger (Part 6) which is the safety-net. The primary
-- invocation for execute_action_v2 is handled by the safety-net trigger
-- on application_pipeline_state which fires AFTER UPDATE when stage changes.
-- This is cleaner than modifying the large function.

-- ============================================================================
-- PART 6: Safety-net trigger on application_pipeline_state
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_ensure_stage_evaluations_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Fire on INSERT (first attach) or UPDATE when stage changes
  IF TG_OP = 'INSERT' THEN
    PERFORM ensure_stage_evaluations(NEW.tenant_id, NEW.application_id, NEW.current_stage_id);
  ELSIF TG_OP = 'UPDATE' AND NEW.current_stage_id IS DISTINCT FROM OLD.current_stage_id THEN
    PERFORM ensure_stage_evaluations(NEW.tenant_id, NEW.application_id, NEW.current_stage_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_stage_eval_auto_create
  AFTER INSERT OR UPDATE ON application_pipeline_state
  FOR EACH ROW
  EXECUTE FUNCTION trg_ensure_stage_evaluations_fn();

COMMENT ON TRIGGER trg_stage_eval_auto_create ON application_pipeline_state IS
  'Safety-net: auto-creates stage evaluations on stage entry. Idempotent — safe if also called from RPCs.';

-- ============================================================================
-- PART 7: RLS Policies
-- ============================================================================

ALTER TABLE stage_evaluations ENABLE ROW LEVEL SECURITY;

-- SELECT: tenant-scoped for HR+ roles (anyone who can view evaluations)
CREATE POLICY "Users can view own tenant stage evaluations" ON stage_evaluations
  FOR SELECT USING (tenant_id = get_tenant_id());

-- INSERT: ADMIN+ roles only
CREATE POLICY "Admins can insert stage evaluations" ON stage_evaluations
  FOR INSERT WITH CHECK (tenant_id = get_tenant_id() AND can_manage_settings());

-- UPDATE: ADMIN+ roles only
CREATE POLICY "Admins can update stage evaluations" ON stage_evaluations
  FOR UPDATE USING (tenant_id = get_tenant_id() AND can_manage_settings())
  WITH CHECK (tenant_id = get_tenant_id() AND can_manage_settings());

-- No DELETE policy — soft-delete only (is_active = false)

-- ============================================================================
-- PART 8: Seed function for system default stages
-- ============================================================================

CREATE OR REPLACE FUNCTION seed_default_stage_evaluations(
  p_stage_id UUID,
  p_tenant_id UUID,
  p_stage_type VARCHAR
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_template_name TEXT;
  v_template_id UUID;
BEGIN
  -- Map stage_type to default evaluation template name
  v_template_name := CASE p_stage_type
    WHEN 'screening'    THEN 'HR Screening'
    WHEN 'interview'    THEN 'Technical Interview'
    WHEN 'review'       THEN 'Culture Council'
    WHEN 'final_review' THEN 'Hiring Committee'
    ELSE NULL
  END;

  -- No default template for this stage type
  IF v_template_name IS NULL THEN
    RETURN;
  END IF;

  -- Find the template (tenant-scoped, active, latest version)
  SELECT id INTO v_template_id
  FROM evaluation_templates
  WHERE tenant_id = p_tenant_id
    AND name = v_template_name
    AND is_active = true
    AND is_latest = true
  LIMIT 1;

  -- Template doesn't exist yet — skip silently
  IF v_template_id IS NULL THEN
    RAISE LOG 'SEED_STAGE_EVAL: No template "%" found for tenant=%, skipping', v_template_name, p_tenant_id;
    RETURN;
  END IF;

  -- Insert stage evaluation config
  INSERT INTO stage_evaluations (
    tenant_id, stage_id, evaluation_template_id, execution_order, auto_create, required
  ) VALUES (
    p_tenant_id, p_stage_id, v_template_id, 1, true, false
  )
  ON CONFLICT (tenant_id, stage_id, execution_order, evaluation_template_id) DO NOTHING;

  RAISE LOG 'SEED_STAGE_EVAL: stage=% type=% template=% tenant=%', p_stage_id, p_stage_type, v_template_id, p_tenant_id;
END;
$$;

-- Trigger: auto-seed stage evaluations when system default stages are created
CREATE OR REPLACE FUNCTION trg_seed_stage_evaluations_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only fire for system default stages (tenant_id IS NULL means global/system)
  IF NEW.tenant_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Seed default evaluations for tenant-owned stages
  PERFORM seed_default_stage_evaluations(NEW.id, NEW.tenant_id, NEW.stage_type);

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_stage_evaluations
  AFTER INSERT ON pipeline_stages
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_stage_evaluations_fn();

COMMENT ON FUNCTION seed_default_stage_evaluations IS
  'Seeds default stage evaluation configs based on stage type. Idempotent via ON CONFLICT.';
