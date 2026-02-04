-- ============================================================================
-- TRACKING SERVICE HARDENING MIGRATION
-- ============================================================================
-- This migration hardens the tracking service with:
-- 1. DB-level idempotency via event_hash on history table
-- 2. Refined terminal status trigger (allows metadata updates)
-- 3. Secure atomic functions that verify tenant ownership from DB
-- 4. Pipeline lock to prevent stage edits when applications exist
-- ============================================================================

-- ============================================================================
-- PHASE 1: History Table - Add event_hash for idempotency
-- ============================================================================
-- WHY: Code-level idempotency is fragile. If function logic changes or retries
-- occur, duplicate history entries can be created. DB constraint guarantees it.

ALTER TABLE application_stage_history
ADD COLUMN IF NOT EXISTS event_hash TEXT;

-- Partial unique index (only enforced when event_hash is set)
CREATE UNIQUE INDEX IF NOT EXISTS idx_history_event_hash
ON application_stage_history(event_hash)
WHERE event_hash IS NOT NULL;

-- Backfill existing rows with computed hash
UPDATE application_stage_history
SET event_hash = md5(
  application_id::text || action ||
  COALESCE(from_stage_id::text, 'null') ||
  COALESCE(to_stage_id::text, 'null')
)
WHERE event_hash IS NULL;

-- ============================================================================
-- PHASE 2: Terminal Status Trigger - Refined semantics
-- ============================================================================
-- WHY: Original trigger blocked ALL updates on terminal rows. This prevents
-- legitimate operations like metadata corrections or compliance updates.
-- FIX: Only block STATUS changes from terminal states.

DROP TRIGGER IF EXISTS trg_enforce_terminal_status ON application_pipeline_state;

CREATE OR REPLACE FUNCTION enforce_terminal_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only block if status is changing FROM a terminal state
  IF OLD.status IN ('HIRED', 'REJECTED', 'WITHDRAWN')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'TERMINAL_STATUS_LOCKED: Cannot change status from terminal state: %', OLD.status
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_terminal_status
  BEFORE UPDATE ON application_pipeline_state
  FOR EACH ROW
  EXECUTE FUNCTION enforce_terminal_status();

-- ============================================================================
-- PHASE 3: Return Type for RPCs (Decoupled DTO)
-- ============================================================================
-- WHY: Returning raw table rows couples DB schema to API contract.
-- Any internal schema change becomes an API breaking change.
-- FIX: Define explicit return type that's stable.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tracking_state_result') THEN
    CREATE TYPE tracking_state_result AS (
      id UUID,
      application_id UUID,
      job_id UUID,
      pipeline_id UUID,
      current_stage_id UUID,
      status TEXT,
      entered_stage_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ
    );
  END IF;
END $$;

-- ============================================================================
-- PHASE 4: Secure Atomic Functions
-- ============================================================================
-- WHY: SECURITY DEFINER functions bypass RLS. Original code trusted caller's
-- tenant_id parameter. An attacker could pass any tenant_id and access
-- other tenants' data.
-- FIX: Verify ownership by querying actual DB rows, not trusting parameters.

-- -----------------------------------------------------------------------------
-- 4.1: attach_application_to_pipeline_v1
-- -----------------------------------------------------------------------------
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

  -- Log for observability
  RAISE LOG 'TRACKING_ATTACH: app=% tenant=% pipeline=%', p_application_id, p_tenant_id, p_pipeline_id;

  -- Return decoupled DTO (not raw table row)
  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
  RETURN v_result;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4.2: move_application_stage_v1
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION move_application_stage_v1(
  p_application_id UUID,
  p_tenant_id UUID,
  p_to_stage_id UUID,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS tracking_state_result
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_state application_pipeline_state;
  v_result tracking_state_result;
  v_old_stage_id UUID;
  v_event_hash TEXT;
BEGIN
  -- SECURITY: Get state with row lock, verify from DB not param
  SELECT * INTO v_state
  FROM application_pipeline_state
  WHERE application_id = p_application_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Application state not found'
      USING ERRCODE = 'P0004';
  END IF;

  -- SECURITY: Verify tenant match from ACTUAL row, not trusted param
  IF v_state.tenant_id != p_tenant_id THEN
    RAISE EXCEPTION 'TENANT_MISMATCH: Access denied'
      USING ERRCODE = 'P0002';
  END IF;

  -- Terminal check (trigger is backup, fail fast here for better error)
  IF v_state.status IN ('HIRED', 'REJECTED', 'WITHDRAWN') THEN
    RAISE EXCEPTION 'TERMINAL_STATUS: Cannot move application in status %', v_state.status
      USING ERRCODE = 'P0001';
  END IF;

  -- SECURITY: Verify target stage belongs to same pipeline
  IF NOT EXISTS (
    SELECT 1 FROM pipeline_stages
    WHERE id = p_to_stage_id AND pipeline_id = v_state.pipeline_id
  ) THEN
    RAISE EXCEPTION 'INVALID_STAGE: Stage does not belong to pipeline'
      USING ERRCODE = 'P0003';
  END IF;

  -- IDEMPOTENCY: Already at target stage? Return current state, no history
  IF v_state.current_stage_id = p_to_stage_id THEN
    v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
                 v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
    RETURN v_result;
  END IF;

  v_old_stage_id := v_state.current_stage_id;

  -- Update state (atomic with history insert)
  UPDATE application_pipeline_state
  SET current_stage_id = p_to_stage_id, entered_stage_at = NOW()
  WHERE id = v_state.id
  RETURNING * INTO v_state;

  -- Compute event hash for this specific transition
  v_event_hash := md5(p_application_id::text || 'MOVE' || v_old_stage_id::text || p_to_stage_id::text);

  -- Insert history with idempotency guard
  INSERT INTO application_stage_history (
    tenant_id, application_id, pipeline_id,
    from_stage_id, to_stage_id, action, changed_by, reason, event_hash
  ) VALUES (
    p_tenant_id, p_application_id, v_state.pipeline_id,
    v_old_stage_id, p_to_stage_id, 'MOVE', p_user_id, p_reason, v_event_hash
  )
  ON CONFLICT (event_hash) WHERE event_hash IS NOT NULL DO NOTHING;

  RAISE LOG 'TRACKING_MOVE: app=% from=% to=%', p_application_id, v_old_stage_id, p_to_stage_id;

  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
  RETURN v_result;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4.3: update_application_status_v1
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_application_status_v1(
  p_application_id UUID,
  p_tenant_id UUID,
  p_status TEXT,
  p_user_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS tracking_state_result
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_state application_pipeline_state;
  v_result tracking_state_result;
  v_action TEXT;
  v_event_hash TEXT;
BEGIN
  -- SECURITY: Get state with lock
  SELECT * INTO v_state
  FROM application_pipeline_state
  WHERE application_id = p_application_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Application state not found'
      USING ERRCODE = 'P0004';
  END IF;

  -- SECURITY: Verify tenant from actual row
  IF v_state.tenant_id != p_tenant_id THEN
    RAISE EXCEPTION 'TENANT_MISMATCH: Access denied'
      USING ERRCODE = 'P0002';
  END IF;

  -- Terminal check
  IF v_state.status IN ('HIRED', 'REJECTED', 'WITHDRAWN') THEN
    RAISE EXCEPTION 'TERMINAL_STATUS: Cannot change status from %', v_state.status
      USING ERRCODE = 'P0001';
  END IF;

  -- IDEMPOTENCY: Already at target status? Return current, no history
  IF v_state.status = p_status THEN
    v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
                 v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
    RETURN v_result;
  END IF;

  -- Map status to action for history
  v_action := CASE p_status
    WHEN 'HIRED' THEN 'HIRE'
    WHEN 'REJECTED' THEN 'REJECT'
    WHEN 'WITHDRAWN' THEN 'WITHDRAW'
    WHEN 'ON_HOLD' THEN 'HOLD'
    WHEN 'ACTIVE' THEN 'ACTIVATE'
    ELSE 'MOVE'
  END;

  -- Update status
  UPDATE application_pipeline_state
  SET status = p_status
  WHERE id = v_state.id
  RETURNING * INTO v_state;

  -- Compute event hash (unique per status change)
  v_event_hash := md5(p_application_id::text || v_action || v_state.current_stage_id::text || p_status);

  -- Insert history
  INSERT INTO application_stage_history (
    tenant_id, application_id, pipeline_id,
    from_stage_id, to_stage_id, action, changed_by, reason, event_hash
  ) VALUES (
    p_tenant_id, p_application_id, v_state.pipeline_id,
    v_state.current_stage_id, v_state.current_stage_id, v_action, p_user_id, p_reason, v_event_hash
  )
  ON CONFLICT (event_hash) WHERE event_hash IS NOT NULL DO NOTHING;

  RAISE LOG 'TRACKING_STATUS: app=% status=%', p_application_id, p_status;

  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
  RETURN v_result;
END;
$$;

-- ============================================================================
-- PHASE 5: Pipeline Stage Mutation Lock
-- ============================================================================
-- WHY: If pipeline stages are edited after applications exist, tracking
-- references become invalid ("ghost stages"). This causes data integrity issues.
-- FIX: Prevent stage edits once any application uses the pipeline.

CREATE OR REPLACE FUNCTION pipeline_has_applications(p_pipeline_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM application_pipeline_state
    WHERE pipeline_id = p_pipeline_id
  );
$$;

CREATE OR REPLACE FUNCTION prevent_pipeline_stage_edit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only check if stages column is being modified
  IF OLD.stages IS DISTINCT FROM NEW.stages
     AND pipeline_has_applications(OLD.id) THEN
    RAISE EXCEPTION 'PIPELINE_LOCKED: Cannot modify stages - applications exist in this pipeline'
      USING ERRCODE = 'P0005';
  END IF;
  RETURN NEW;
END;
$$;

-- Drop if exists to avoid duplicate trigger
DROP TRIGGER IF EXISTS trg_prevent_pipeline_stage_edit ON pipelines;

CREATE TRIGGER trg_prevent_pipeline_stage_edit
  BEFORE UPDATE ON pipelines
  FOR EACH ROW
  EXECUTE FUNCTION prevent_pipeline_stage_edit();

-- ============================================================================
-- DONE
-- ============================================================================
