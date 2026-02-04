-- ============================================================================
-- ACTION ENGINE MIGRATION
-- ============================================================================
-- 1. Create stage_actions table (global action definitions per stage type)
-- 2. Seed default actions for all 4 stage types
-- 3. RLS policies
-- 4. Create execute_action_v1 RPC
-- ============================================================================

-- ============================================================================
-- PHASE 1: Create stage_actions table
-- ============================================================================

CREATE TABLE IF NOT EXISTS stage_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stage_type VARCHAR(50) NOT NULL,
  action_code VARCHAR(50) NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  target_status VARCHAR(50),
  moves_to_next_stage BOOLEAN DEFAULT FALSE,
  is_terminal BOOLEAN DEFAULT FALSE,
  requires_feedback BOOLEAN DEFAULT FALSE,
  requires_notes BOOLEAN DEFAULT FALSE,
  allowed_roles TEXT[] NOT NULL DEFAULT '{ADMIN,HR}',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(stage_type, action_code)
);

CREATE INDEX IF NOT EXISTS idx_stage_actions_stage_type ON stage_actions(stage_type);

-- ============================================================================
-- PHASE 2: Seed default actions per stage type
-- ============================================================================

INSERT INTO stage_actions
  (stage_type, action_code, display_name, target_status, moves_to_next_stage, is_terminal, requires_feedback, requires_notes, allowed_roles, sort_order)
VALUES
  -- SCREENING actions
  ('screening', 'COMPLETE',  'Complete Screening',     NULL,        TRUE,  FALSE, FALSE, FALSE, '{ADMIN,HR}',             1),
  ('screening', 'FAIL',      'Reject at Screening',    'REJECTED',  FALSE, TRUE,  FALSE, TRUE,  '{ADMIN,HR}',             2),
  ('screening', 'SKIP',      'Skip Screening',         NULL,        TRUE,  FALSE, FALSE, TRUE,  '{ADMIN,HR}',             3),
  ('screening', 'HOLD',      'Put on Hold',            'ON_HOLD',   FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             4),
  ('screening', 'ACTIVATE',  'Reactivate',             'ACTIVE',    FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             5),

  -- INTERVIEW actions
  ('interview', 'COMPLETE',  'Complete Interview',     NULL,        TRUE,  FALSE, TRUE,  FALSE, '{ADMIN,HR,INTERVIEWER}',  1),
  ('interview', 'FAIL',      'Reject after Interview', 'REJECTED',  FALSE, TRUE,  TRUE,  TRUE,  '{ADMIN,HR}',             2),
  ('interview', 'SKIP',      'Skip Interview',         NULL,        TRUE,  FALSE, FALSE, TRUE,  '{ADMIN,HR}',             3),
  ('interview', 'HOLD',      'Put on Hold',            'ON_HOLD',   FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             4),
  ('interview', 'ACTIVATE',  'Reactivate',             'ACTIVE',    FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             5),

  -- DECISION actions
  ('decision',  'COMPLETE',  'Advance to Outcome',     NULL,        TRUE,  FALSE, FALSE, TRUE,  '{ADMIN,HR}',             1),
  ('decision',  'HIRE',      'Hire Candidate',         'HIRED',     FALSE, TRUE,  FALSE, TRUE,  '{ADMIN,HR}',             2),
  ('decision',  'FAIL',      'Reject Candidate',       'REJECTED',  FALSE, TRUE,  FALSE, TRUE,  '{ADMIN,HR}',             3),
  ('decision',  'HOLD',      'Put on Hold',            'ON_HOLD',   FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             4),
  ('decision',  'ACTIVATE',  'Reactivate',             'ACTIVE',    FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             5),

  -- OUTCOME actions
  ('outcome',   'HIRE',      'Confirm Hire',           'HIRED',     FALSE, TRUE,  FALSE, TRUE,  '{ADMIN,HR}',             1),
  ('outcome',   'FAIL',      'Reject Candidate',       'REJECTED',  FALSE, TRUE,  FALSE, TRUE,  '{ADMIN,HR}',             2),
  ('outcome',   'HOLD',      'Put on Hold',            'ON_HOLD',   FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             3),
  ('outcome',   'ACTIVATE',  'Reactivate',             'ACTIVE',    FALSE, FALSE, FALSE, TRUE,  '{ADMIN,HR}',             4)
ON CONFLICT (stage_type, action_code) DO NOTHING;

-- ============================================================================
-- PHASE 3: RLS policies for stage_actions
-- ============================================================================

ALTER TABLE stage_actions ENABLE ROW LEVEL SECURITY;

-- Everyone can read (UI needs to know available actions)
CREATE POLICY "Authenticated users can view stage actions" ON stage_actions
  FOR SELECT USING (true);

-- Only SUPERADMIN can modify (system-level config)
CREATE POLICY "Superadmin can manage stage actions" ON stage_actions
  FOR ALL USING (public.is_superadmin());

-- ============================================================================
-- PHASE 4: execute_action_v1 RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION execute_action_v1(
  p_application_id UUID,
  p_tenant_id UUID,
  p_user_id UUID,
  p_user_role TEXT,
  p_action_code TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS tracking_state_result
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_state application_pipeline_state;
  v_result tracking_state_result;
  v_current_stage pipeline_stages;
  v_next_stage pipeline_stages;
  v_action stage_actions;
  v_event_hash TEXT;
  v_new_stage_id UUID;
  v_new_status TEXT;
  v_is_current_terminal BOOLEAN;
  v_feedback_count INT;
BEGIN
  -- ================================================================
  -- STEP 1: Lock and load application state
  -- ================================================================
  SELECT * INTO v_state
  FROM application_pipeline_state
  WHERE application_id = p_application_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Application state not found'
      USING ERRCODE = 'P0004';
  END IF;

  -- SECURITY: Verify tenant from actual DB row
  IF v_state.tenant_id != p_tenant_id THEN
    RAISE EXCEPTION 'TENANT_MISMATCH: Access denied'
      USING ERRCODE = 'P0002';
  END IF;

  -- ================================================================
  -- STEP 2: Get current stage details
  -- ================================================================
  SELECT * INTO v_current_stage
  FROM pipeline_stages
  WHERE id = v_state.current_stage_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Current stage not found (data integrity error)'
      USING ERRCODE = 'P0004';
  END IF;

  -- ================================================================
  -- STEP 3: Check current status is not terminal
  -- ================================================================
  SELECT is_terminal INTO v_is_current_terminal
  FROM tenant_application_statuses
  WHERE tenant_id = v_state.tenant_id
    AND status_code = v_state.status
    AND is_active = TRUE;

  IF v_is_current_terminal = TRUE THEN
    RAISE EXCEPTION 'TERMINAL_STATUS: Cannot perform actions on application in terminal status %', v_state.status
      USING ERRCODE = 'P0001';
  END IF;

  -- ================================================================
  -- STEP 4: Validate action is allowed for this stage_type
  -- ================================================================
  SELECT * INTO v_action
  FROM stage_actions
  WHERE stage_type = v_current_stage.stage_type
    AND action_code = p_action_code;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_ACTION: Action "%" is not allowed for stage type "%"', p_action_code, v_current_stage.stage_type
      USING ERRCODE = 'P0007';
  END IF;

  -- ================================================================
  -- STEP 5: Validate user role is in allowed_roles
  -- ================================================================
  IF NOT (p_user_role = ANY(v_action.allowed_roles)) THEN
    RAISE EXCEPTION 'FORBIDDEN: Role "%" is not authorized for action "%" on stage type "%"', p_user_role, p_action_code, v_current_stage.stage_type
      USING ERRCODE = 'P0008';
  END IF;

  -- ================================================================
  -- STEP 6: Validate notes if required
  -- ================================================================
  IF v_action.requires_notes = TRUE AND (p_notes IS NULL OR TRIM(p_notes) = '') THEN
    RAISE EXCEPTION 'VALIDATION: Notes are required for action "%"', p_action_code
      USING ERRCODE = 'P0009';
  END IF;

  -- ================================================================
  -- STEP 7: Validate feedback exists if required
  -- ================================================================
  IF v_action.requires_feedback = TRUE THEN
    SELECT COUNT(*) INTO v_feedback_count
    FROM stage_feedback
    WHERE tenant_id = p_tenant_id
      AND application_id = p_application_id
      AND stage_name = v_current_stage.stage_name;

    IF v_feedback_count = 0 THEN
      RAISE EXCEPTION 'FEEDBACK_REQUIRED: Feedback must be submitted before action "%" on stage "%"', p_action_code, v_current_stage.stage_name
        USING ERRCODE = 'P0010';
    END IF;
  END IF;

  -- ================================================================
  -- STEP 8: HOLD/ACTIVATE status guards
  -- ================================================================
  IF p_action_code = 'HOLD' AND v_state.status != 'ACTIVE' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot hold application that is not ACTIVE (current: %)', v_state.status
      USING ERRCODE = 'P0007';
  END IF;

  IF p_action_code = 'ACTIVATE' AND v_state.status != 'ON_HOLD' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot activate application that is not ON_HOLD (current: %)', v_state.status
      USING ERRCODE = 'P0007';
  END IF;

  -- ================================================================
  -- STEP 9: Compute next stage and status
  -- ================================================================
  v_new_stage_id := v_state.current_stage_id;
  v_new_status := v_state.status;

  -- Move to next stage if action requires it
  IF v_action.moves_to_next_stage = TRUE THEN
    SELECT * INTO v_next_stage
    FROM pipeline_stages
    WHERE pipeline_id = v_state.pipeline_id
      AND order_index = v_current_stage.order_index + 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'INVALID_ACTION: Already at the last stage - cannot advance further. Use HIRE or FAIL instead.'
        USING ERRCODE = 'P0007';
    END IF;

    v_new_stage_id := v_next_stage.id;
  END IF;

  -- Apply target_status if action defines one
  IF v_action.target_status IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM tenant_application_statuses
      WHERE tenant_id = p_tenant_id
        AND status_code = v_action.target_status
        AND is_active = TRUE
    ) THEN
      RAISE EXCEPTION 'INVALID_STATUS: Target status "%" not configured for tenant', v_action.target_status
        USING ERRCODE = 'P0006';
    END IF;

    v_new_status := v_action.target_status;
  END IF;

  -- ================================================================
  -- STEP 10: Idempotency check
  -- ================================================================
  v_event_hash := md5(
    p_application_id::text || p_action_code ||
    v_state.current_stage_id::text || v_new_stage_id::text ||
    COALESCE(v_new_status, 'null')
  );

  IF v_new_stage_id = v_state.current_stage_id AND v_new_status = v_state.status THEN
    v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
                 v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
    RETURN v_result;
  END IF;

  -- ================================================================
  -- STEP 11: Execute the mutation
  -- ================================================================
  UPDATE application_pipeline_state
  SET
    current_stage_id = v_new_stage_id,
    status = v_new_status,
    entered_stage_at = CASE WHEN v_new_stage_id != v_state.current_stage_id THEN NOW() ELSE entered_stage_at END,
    updated_at = NOW()
  WHERE id = v_state.id
  RETURNING * INTO v_state;

  -- ================================================================
  -- STEP 12: Record history
  -- ================================================================
  INSERT INTO application_stage_history (
    tenant_id, application_id, pipeline_id,
    from_stage_id, to_stage_id, action, changed_by, reason, event_hash
  ) VALUES (
    p_tenant_id, p_application_id, v_state.pipeline_id,
    v_current_stage.id, v_new_stage_id, p_action_code, p_user_id, p_notes, v_event_hash
  )
  ON CONFLICT (event_hash) WHERE event_hash IS NOT NULL DO NOTHING;

  -- ================================================================
  -- STEP 13: Log and return
  -- ================================================================
  RAISE LOG 'ACTION_ENGINE: app=% action=% from_stage=% to_stage=% status=%',
    p_application_id, p_action_code, v_current_stage.id, v_new_stage_id, v_new_status;

  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at);
  RETURN v_result;
END;
$$;
