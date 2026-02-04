-- ============================================================================
-- TENANT-CONFIGURABLE STATUSES MIGRATION
-- ============================================================================
-- This migration makes application statuses tenant-configurable:
-- 1. Creates tenant_application_statuses table
-- 2. Seeds default statuses for existing tenants
-- 3. Auto-seeds new tenants via trigger
-- 4. Updates terminal trigger to use dynamic lookup
-- 5. Updates RPCs to use dynamic status/action lookup
-- 6. Drops hardcoded CHECK constraints
-- 7. Adds RLS policies
-- ============================================================================

-- ============================================================================
-- PHASE 1: Create tenant_application_statuses table
-- ============================================================================

CREATE TABLE IF NOT EXISTS tenant_application_statuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  status_code VARCHAR(50) NOT NULL,      -- 'HIRED', 'PLACED', etc.
  display_name VARCHAR(100) NOT NULL,    -- 'Hired', 'Placement Complete'
  action_code VARCHAR(50) NOT NULL,      -- 'HIRE', 'PLACE' (for history)
  is_terminal BOOLEAN DEFAULT FALSE,     -- Can't change from this status
  is_active BOOLEAN DEFAULT TRUE,        -- Soft delete
  sort_order INT DEFAULT 0,              -- UI ordering
  color_hex VARCHAR(7),                  -- '#22C55E' (optional)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, status_code)
);

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_tenant_statuses_tenant_active
ON tenant_application_statuses(tenant_id, is_active);

-- ============================================================================
-- PHASE 2: Seed default statuses function
-- ============================================================================

CREATE OR REPLACE FUNCTION seed_default_statuses(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  -- Insert default statuses if not exists
  INSERT INTO tenant_application_statuses
    (tenant_id, status_code, display_name, action_code, is_terminal, sort_order, color_hex)
  VALUES
    (p_tenant_id, 'ACTIVE', 'Active', 'ACTIVATE', FALSE, 1, '#3B82F6'),
    (p_tenant_id, 'ON_HOLD', 'On Hold', 'HOLD', FALSE, 2, '#F59E0B'),
    (p_tenant_id, 'HIRED', 'Hired', 'HIRE', TRUE, 3, '#22C55E'),
    (p_tenant_id, 'REJECTED', 'Rejected', 'REJECT', TRUE, 4, '#EF4444'),
    (p_tenant_id, 'WITHDRAWN', 'Withdrawn', 'WITHDRAW', TRUE, 5, '#6B7280')
  ON CONFLICT (tenant_id, status_code) DO NOTHING;
END;
$$;

-- ============================================================================
-- PHASE 3: Backfill existing tenants with default statuses
-- ============================================================================

DO $$
DECLARE
  v_tenant RECORD;
BEGIN
  FOR v_tenant IN SELECT id FROM tenants LOOP
    PERFORM seed_default_statuses(v_tenant.id);
  END LOOP;
END;
$$;

-- ============================================================================
-- PHASE 4: Trigger to auto-seed new tenants
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_seed_tenant_statuses()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM seed_default_statuses(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seed_tenant_statuses ON tenants;

CREATE TRIGGER trg_seed_tenant_statuses
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_tenant_statuses();

-- ============================================================================
-- PHASE 5: Validate status exists for tenant (replaces CHECK constraint)
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_status_for_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM tenant_application_statuses
    WHERE tenant_id = NEW.tenant_id
      AND status_code = NEW.status
      AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'INVALID_STATUS: Status "%" not configured for tenant', NEW.status
      USING ERRCODE = 'P0006';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_status ON application_pipeline_state;

CREATE TRIGGER trg_validate_status
  BEFORE INSERT OR UPDATE OF status ON application_pipeline_state
  FOR EACH ROW
  EXECUTE FUNCTION validate_status_for_tenant();

-- ============================================================================
-- PHASE 6: Update terminal status trigger to use dynamic lookup
-- ============================================================================

CREATE OR REPLACE FUNCTION enforce_terminal_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_is_terminal BOOLEAN;
BEGIN
  -- Look up if OLD status is terminal for this tenant
  SELECT is_terminal INTO v_is_terminal
  FROM tenant_application_statuses
  WHERE tenant_id = OLD.tenant_id
    AND status_code = OLD.status
    AND is_active = TRUE;

  -- If status is terminal and we're trying to change it, block
  IF v_is_terminal = TRUE AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'TERMINAL_STATUS_LOCKED: Cannot change status from terminal state: %', OLD.status
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger already exists from previous migration, function is replaced

-- ============================================================================
-- PHASE 7: Drop hardcoded CHECK constraints
-- ============================================================================

-- Drop CHECK constraint on application_pipeline_state.status
ALTER TABLE application_pipeline_state
DROP CONSTRAINT IF EXISTS application_pipeline_state_status_check;

-- Drop CHECK constraint on application_stage_history.action
ALTER TABLE application_stage_history
DROP CONSTRAINT IF EXISTS application_stage_history_action_check;

-- ============================================================================
-- PHASE 8: Update RPCs to use dynamic status lookup
-- ============================================================================

-- 8.1: update_application_status_v1 - use dynamic action lookup
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
  v_is_old_terminal BOOLEAN;
  v_status_exists BOOLEAN;
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

  -- VALIDATION: Check if target status exists for tenant
  SELECT EXISTS (
    SELECT 1 FROM tenant_application_statuses
    WHERE tenant_id = p_tenant_id AND status_code = p_status AND is_active = TRUE
  ) INTO v_status_exists;

  IF NOT v_status_exists THEN
    RAISE EXCEPTION 'INVALID_STATUS: Status "%" not configured for tenant', p_status
      USING ERRCODE = 'P0006';
  END IF;

  -- Terminal check using dynamic lookup
  SELECT is_terminal INTO v_is_old_terminal
  FROM tenant_application_statuses
  WHERE tenant_id = v_state.tenant_id AND status_code = v_state.status AND is_active = TRUE;

  IF v_is_old_terminal = TRUE THEN
    RAISE EXCEPTION 'TERMINAL_STATUS: Cannot change status from %', v_state.status
      USING ERRCODE = 'P0001';
  END IF;

  -- IDEMPOTENCY: Already at target status? Return current, no history
  IF v_state.status = p_status THEN
    v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
                 v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
    RETURN v_result;
  END IF;

  -- Get action_code from tenant status config (dynamic, not hardcoded)
  SELECT action_code INTO v_action
  FROM tenant_application_statuses
  WHERE tenant_id = p_tenant_id AND status_code = p_status AND is_active = TRUE;

  -- Fallback if somehow not found (shouldn't happen due to validation above)
  IF v_action IS NULL THEN
    v_action := 'MOVE';
  END IF;

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

-- 8.2: move_application_stage_v1 - use dynamic terminal check
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
  v_is_terminal BOOLEAN;
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

  -- Terminal check using dynamic lookup (not hardcoded statuses)
  SELECT is_terminal INTO v_is_terminal
  FROM tenant_application_statuses
  WHERE tenant_id = v_state.tenant_id AND status_code = v_state.status AND is_active = TRUE;

  IF v_is_terminal = TRUE THEN
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

-- ============================================================================
-- PHASE 9: Enable RLS and add policies for tenant_application_statuses
-- ============================================================================

ALTER TABLE tenant_application_statuses ENABLE ROW LEVEL SECURITY;

-- SUPERADMIN: full access
CREATE POLICY "Superadmin full access to statuses" ON tenant_application_statuses
  FOR ALL USING (public.is_superadmin());

-- All users in tenant: view statuses
CREATE POLICY "Users can view tenant statuses" ON tenant_application_statuses
  FOR SELECT USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
  );

-- ADMIN only: manage statuses
CREATE POLICY "Admin can manage statuses" ON tenant_application_statuses
  FOR ALL USING (
    NOT public.is_superadmin()
    AND tenant_id = public.get_tenant_id()
    AND public.can_manage_settings()
  );

-- ============================================================================
-- PHASE 10: Helper function to get statuses for a tenant
-- ============================================================================

CREATE OR REPLACE FUNCTION get_tenant_statuses(p_tenant_id UUID)
RETURNS TABLE (
  id UUID,
  status_code VARCHAR(50),
  display_name VARCHAR(100),
  action_code VARCHAR(50),
  is_terminal BOOLEAN,
  sort_order INT,
  color_hex VARCHAR(7)
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    id,
    status_code,
    display_name,
    action_code,
    is_terminal,
    sort_order,
    color_hex
  FROM tenant_application_statuses
  WHERE tenant_id = p_tenant_id
    AND is_active = TRUE
  ORDER BY sort_order;
$$;

-- ============================================================================
-- DONE
-- ============================================================================
