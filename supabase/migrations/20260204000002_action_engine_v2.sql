-- ============================================================================
-- ACTION ENGINE V2 MIGRATION
-- ============================================================================
-- Outcome-based, capability-driven action engine.
--
-- Part 1: Add outcome_type/is_terminal to application_pipeline_state
-- Part 2: Add outcome_type to tenant_application_statuses
-- Part 3: Drop old stage_actions, create tenant_stage_actions (stage_id scoped)
-- Part 4: Create role_capabilities table
-- Part 5: Seed functions + triggers + backfill
-- Part 6: RLS policies
-- Part 7: execute_action_v2 RPC
-- ============================================================================

-- ============================================================================
-- PART 1: Outcome as primary state in application_pipeline_state
-- ============================================================================

ALTER TABLE application_pipeline_state
  ADD COLUMN outcome_type VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
    CHECK (outcome_type IN ('ACTIVE','HOLD','SUCCESS','FAILURE','NEUTRAL')),
  ADD COLUMN is_terminal BOOLEAN NOT NULL DEFAULT FALSE;

-- Extend the composite return type
ALTER TYPE tracking_state_result ADD ATTRIBUTE outcome_type text;
ALTER TYPE tracking_state_result ADD ATTRIBUTE is_terminal boolean;

-- ============================================================================
-- PART 2: Add outcome_type to tenant_application_statuses
-- ============================================================================

ALTER TABLE tenant_application_statuses
  ADD COLUMN outcome_type VARCHAR(20) NOT NULL DEFAULT 'NEUTRAL'
    CHECK (outcome_type IN ('ACTIVE','HOLD','SUCCESS','FAILURE','NEUTRAL'));

-- Backfill existing seeded statuses
UPDATE tenant_application_statuses SET outcome_type = 'ACTIVE'  WHERE status_code = 'ACTIVE';
UPDATE tenant_application_statuses SET outcome_type = 'HOLD'    WHERE status_code = 'ON_HOLD';
UPDATE tenant_application_statuses SET outcome_type = 'SUCCESS' WHERE status_code = 'HIRED';
UPDATE tenant_application_statuses SET outcome_type = 'FAILURE' WHERE status_code = 'REJECTED';
-- WITHDRAWN keeps default 'NEUTRAL'

-- Backfill application_pipeline_state from tenant_application_statuses
UPDATE application_pipeline_state aps
SET outcome_type = COALESCE(tas.outcome_type, 'ACTIVE'),
    is_terminal  = COALESCE(tas.is_terminal, FALSE)
FROM tenant_application_statuses tas
WHERE tas.tenant_id = aps.tenant_id
  AND tas.status_code = aps.status;

-- Update seed_default_statuses to include outcome_type
CREATE OR REPLACE FUNCTION seed_default_statuses(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO tenant_application_statuses
    (tenant_id, status_code, display_name, action_code, is_terminal, sort_order, color_hex, outcome_type)
  VALUES
    (p_tenant_id, 'ACTIVE',    'Active',    'ACTIVATE', FALSE, 1, '#3B82F6', 'ACTIVE'),
    (p_tenant_id, 'ON_HOLD',   'On Hold',   'HOLD',     FALSE, 2, '#F59E0B', 'HOLD'),
    (p_tenant_id, 'HIRED',     'Hired',     'HIRE',     TRUE,  3, '#22C55E', 'SUCCESS'),
    (p_tenant_id, 'REJECTED',  'Rejected',  'REJECT',   TRUE,  4, '#EF4444', 'FAILURE'),
    (p_tenant_id, 'WITHDRAWN', 'Withdrawn', 'WITHDRAW', TRUE,  5, '#6B7280', 'NEUTRAL')
  ON CONFLICT (tenant_id, status_code) DO NOTHING;
END;
$$;

-- ============================================================================
-- PART 3: Drop old table, create tenant_stage_actions (scoped to stage_id)
-- ============================================================================

-- Drop the v1 RPC first (references stage_actions)
DROP FUNCTION IF EXISTS execute_action_v1(UUID, UUID, UUID, TEXT, TEXT, TEXT);

-- Drop old table and its policies
DROP TABLE IF EXISTS stage_actions CASCADE;

CREATE TABLE tenant_stage_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  stage_id UUID NOT NULL REFERENCES pipeline_stages(id) ON DELETE CASCADE,
  action_code VARCHAR(50) NOT NULL,
  display_name VARCHAR(100) NOT NULL,
  outcome_type VARCHAR(20) DEFAULT NULL
    CHECK (outcome_type IS NULL OR outcome_type IN ('ACTIVE','HOLD','SUCCESS','FAILURE','NEUTRAL')),
  moves_to_next_stage BOOLEAN DEFAULT FALSE,
  is_terminal BOOLEAN DEFAULT FALSE,
  requires_feedback BOOLEAN DEFAULT FALSE,
  requires_notes BOOLEAN DEFAULT FALSE,
  required_capability VARCHAR(50) NOT NULL DEFAULT 'ADVANCE_STAGE',
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, stage_id, action_code)
);

CREATE INDEX idx_tenant_stage_actions_stage ON tenant_stage_actions(stage_id);
CREATE INDEX idx_tenant_stage_actions_tenant ON tenant_stage_actions(tenant_id);

-- ============================================================================
-- PART 4: Create role_capabilities table
-- ============================================================================

CREATE TABLE role_capabilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  role_name VARCHAR(50) NOT NULL,
  capability VARCHAR(50) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, role_name, capability)
);

CREATE INDEX idx_role_capabilities_lookup
  ON role_capabilities(tenant_id, role_name);

-- ============================================================================
-- PART 5: Seed functions + triggers + backfill
-- ============================================================================

-- Seed default stage actions for a single stage
CREATE OR REPLACE FUNCTION seed_default_stage_actions(
  p_stage_id UUID,
  p_tenant_id UUID,
  p_stage_type VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_stage_type = 'screening' THEN
    INSERT INTO tenant_stage_actions
      (tenant_id, stage_id, action_code, display_name, outcome_type, moves_to_next_stage, is_terminal, requires_feedback, requires_notes, required_capability, sort_order)
    VALUES
      (p_tenant_id, p_stage_id, 'ADVANCE',  'Advance',     NULL,      TRUE,  FALSE, FALSE, FALSE, 'ADVANCE_STAGE',          1),
      (p_tenant_id, p_stage_id, 'REJECT',   'Reject',      'FAILURE', FALSE, TRUE,  FALSE, TRUE,  'TERMINATE_APPLICATION',  2),
      (p_tenant_id, p_stage_id, 'SKIP',     'Skip Stage',  NULL,      TRUE,  FALSE, FALSE, TRUE,  'OVERRIDE_FLOW',          3),
      (p_tenant_id, p_stage_id, 'HOLD',     'Hold',        'HOLD',    FALSE, FALSE, FALSE, TRUE,  'CHANGE_STATUS',          4),
      (p_tenant_id, p_stage_id, 'ACTIVATE', 'Reactivate',  'ACTIVE',  FALSE, FALSE, FALSE, FALSE, 'CHANGE_STATUS',          5)
    ON CONFLICT (tenant_id, stage_id, action_code) DO NOTHING;

  ELSIF p_stage_type = 'interview' THEN
    INSERT INTO tenant_stage_actions
      (tenant_id, stage_id, action_code, display_name, outcome_type, moves_to_next_stage, is_terminal, requires_feedback, requires_notes, required_capability, sort_order)
    VALUES
      (p_tenant_id, p_stage_id, 'ADVANCE',  'Advance',     NULL,      TRUE,  FALSE, TRUE,  FALSE, 'ADVANCE_STAGE',          1),
      (p_tenant_id, p_stage_id, 'REJECT',   'Reject',      'FAILURE', FALSE, TRUE,  TRUE,  TRUE,  'TERMINATE_APPLICATION',  2),
      (p_tenant_id, p_stage_id, 'SKIP',     'Skip Stage',  NULL,      TRUE,  FALSE, FALSE, TRUE,  'OVERRIDE_FLOW',          3),
      (p_tenant_id, p_stage_id, 'HOLD',     'Hold',        'HOLD',    FALSE, FALSE, FALSE, TRUE,  'CHANGE_STATUS',          4),
      (p_tenant_id, p_stage_id, 'ACTIVATE', 'Reactivate',  'ACTIVE',  FALSE, FALSE, FALSE, FALSE, 'CHANGE_STATUS',          5)
    ON CONFLICT (tenant_id, stage_id, action_code) DO NOTHING;

  ELSIF p_stage_type = 'decision' THEN
    INSERT INTO tenant_stage_actions
      (tenant_id, stage_id, action_code, display_name, outcome_type, moves_to_next_stage, is_terminal, requires_feedback, requires_notes, required_capability, sort_order)
    VALUES
      (p_tenant_id, p_stage_id, 'ADVANCE',  'Advance',     NULL,      TRUE,  FALSE, FALSE, TRUE,  'ADVANCE_STAGE',          1),
      (p_tenant_id, p_stage_id, 'APPROVE',  'Approve',     'SUCCESS', FALSE, TRUE,  FALSE, TRUE,  'TERMINATE_APPLICATION',  2),
      (p_tenant_id, p_stage_id, 'REJECT',   'Reject',      'FAILURE', FALSE, TRUE,  FALSE, TRUE,  'TERMINATE_APPLICATION',  3),
      (p_tenant_id, p_stage_id, 'HOLD',     'Hold',        'HOLD',    FALSE, FALSE, FALSE, TRUE,  'CHANGE_STATUS',          4),
      (p_tenant_id, p_stage_id, 'ACTIVATE', 'Reactivate',  'ACTIVE',  FALSE, FALSE, FALSE, FALSE, 'CHANGE_STATUS',          5)
    ON CONFLICT (tenant_id, stage_id, action_code) DO NOTHING;

  ELSIF p_stage_type = 'outcome' THEN
    INSERT INTO tenant_stage_actions
      (tenant_id, stage_id, action_code, display_name, outcome_type, moves_to_next_stage, is_terminal, requires_feedback, requires_notes, required_capability, sort_order)
    VALUES
      (p_tenant_id, p_stage_id, 'APPROVE',  'Approve',     'SUCCESS', FALSE, TRUE,  FALSE, TRUE,  'TERMINATE_APPLICATION',  1),
      (p_tenant_id, p_stage_id, 'REJECT',   'Reject',      'FAILURE', FALSE, TRUE,  FALSE, TRUE,  'TERMINATE_APPLICATION',  2),
      (p_tenant_id, p_stage_id, 'HOLD',     'Hold',        'HOLD',    FALSE, FALSE, FALSE, TRUE,  'CHANGE_STATUS',          3),
      (p_tenant_id, p_stage_id, 'ACTIVATE', 'Reactivate',  'ACTIVE',  FALSE, FALSE, FALSE, FALSE, 'CHANGE_STATUS',          4)
    ON CONFLICT (tenant_id, stage_id, action_code) DO NOTHING;
  END IF;
END;
$$;

-- Seed default capabilities for a tenant
CREATE OR REPLACE FUNCTION seed_default_capabilities(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO role_capabilities (tenant_id, role_name, capability)
  VALUES
    -- SUPERADMIN: all capabilities
    (p_tenant_id, 'SUPERADMIN', 'ADVANCE_STAGE'),
    (p_tenant_id, 'SUPERADMIN', 'TERMINATE_APPLICATION'),
    (p_tenant_id, 'SUPERADMIN', 'CHANGE_STATUS'),
    (p_tenant_id, 'SUPERADMIN', 'PROVIDE_FEEDBACK'),
    (p_tenant_id, 'SUPERADMIN', 'VIEW_TRACKING'),
    (p_tenant_id, 'SUPERADMIN', 'MANAGE_SETTINGS'),
    (p_tenant_id, 'SUPERADMIN', 'OVERRIDE_FLOW'),
    -- ADMIN: all capabilities
    (p_tenant_id, 'ADMIN', 'ADVANCE_STAGE'),
    (p_tenant_id, 'ADMIN', 'TERMINATE_APPLICATION'),
    (p_tenant_id, 'ADMIN', 'CHANGE_STATUS'),
    (p_tenant_id, 'ADMIN', 'PROVIDE_FEEDBACK'),
    (p_tenant_id, 'ADMIN', 'VIEW_TRACKING'),
    (p_tenant_id, 'ADMIN', 'MANAGE_SETTINGS'),
    (p_tenant_id, 'ADMIN', 'OVERRIDE_FLOW'),
    -- HR
    (p_tenant_id, 'HR', 'ADVANCE_STAGE'),
    (p_tenant_id, 'HR', 'TERMINATE_APPLICATION'),
    (p_tenant_id, 'HR', 'CHANGE_STATUS'),
    (p_tenant_id, 'HR', 'PROVIDE_FEEDBACK'),
    (p_tenant_id, 'HR', 'VIEW_TRACKING'),
    -- INTERVIEWER
    (p_tenant_id, 'INTERVIEWER', 'ADVANCE_STAGE'),
    (p_tenant_id, 'INTERVIEWER', 'PROVIDE_FEEDBACK'),
    (p_tenant_id, 'INTERVIEWER', 'VIEW_TRACKING'),
    -- VIEWER
    (p_tenant_id, 'VIEWER', 'VIEW_TRACKING'),
    -- CANDIDATE
    (p_tenant_id, 'CANDIDATE', 'VIEW_TRACKING')
  ON CONFLICT (tenant_id, role_name, capability) DO NOTHING;
END;
$$;

-- Trigger: seed stage actions on pipeline_stages insert
-- Handles global stages (tenant_id IS NULL) by seeding for ALL tenants
CREATE OR REPLACE FUNCTION trg_seed_stage_actions_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  IF NEW.tenant_id IS NOT NULL THEN
    PERFORM seed_default_stage_actions(NEW.id, NEW.tenant_id, NEW.stage_type);
  ELSE
    -- Global stage: seed for every tenant
    FOR v_tenant_id IN SELECT id FROM tenants LOOP
      PERFORM seed_default_stage_actions(NEW.id, v_tenant_id, NEW.stage_type);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_stage_actions
  AFTER INSERT ON pipeline_stages
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_stage_actions_fn();

-- Trigger: seed capabilities on tenant insert
CREATE OR REPLACE FUNCTION trg_seed_capabilities_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM seed_default_capabilities(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_capabilities
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_capabilities_fn();

-- Trigger: when a new tenant is created, seed stage actions for all existing global stages
CREATE OR REPLACE FUNCTION trg_seed_tenant_stage_actions_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stage RECORD;
BEGIN
  FOR v_stage IN SELECT id, stage_type FROM pipeline_stages WHERE tenant_id IS NULL LOOP
    PERFORM seed_default_stage_actions(v_stage.id, NEW.id, v_stage.stage_type);
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_tenant_stage_actions
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_tenant_stage_actions_fn();

-- ============================================================================
-- BACKFILL: Seed capabilities for all existing tenants
-- ============================================================================
DO $$
DECLARE
  v_tenant_id UUID;
BEGIN
  FOR v_tenant_id IN SELECT id FROM tenants LOOP
    PERFORM seed_default_capabilities(v_tenant_id);
  END LOOP;
END;
$$;

-- ============================================================================
-- BACKFILL: Seed stage actions for all existing stages x tenants
-- ============================================================================
DO $$
DECLARE
  v_stage RECORD;
  v_tenant_id UUID;
BEGIN
  FOR v_stage IN SELECT id, tenant_id, stage_type FROM pipeline_stages LOOP
    IF v_stage.tenant_id IS NOT NULL THEN
      PERFORM seed_default_stage_actions(v_stage.id, v_stage.tenant_id, v_stage.stage_type);
    ELSE
      -- Global stage: seed for every tenant
      FOR v_tenant_id IN SELECT id FROM tenants LOOP
        PERFORM seed_default_stage_actions(v_stage.id, v_tenant_id, v_stage.stage_type);
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- PART 6: RLS Policies
-- ============================================================================

-- tenant_stage_actions
ALTER TABLE tenant_stage_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant actions" ON tenant_stage_actions
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "Admins can manage actions" ON tenant_stage_actions
  FOR ALL USING (tenant_id = get_tenant_id() AND can_manage_settings());

-- role_capabilities
ALTER TABLE role_capabilities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant capabilities" ON role_capabilities
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "Admins can manage capabilities" ON role_capabilities
  FOR ALL USING (tenant_id = get_tenant_id() AND can_manage_settings());

-- ============================================================================
-- PART 7: execute_action_v2 RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION execute_action_v2(
  p_application_id UUID,
  p_tenant_id UUID,
  p_user_id UUID,
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
  v_action tenant_stage_actions;
  v_event_hash TEXT;
  v_new_stage_id UUID;
  v_new_status TEXT;
  v_new_outcome VARCHAR(20);
  v_new_is_terminal BOOLEAN;
  v_has_capability BOOLEAN;
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
  -- STEP 2: Check terminal — use is_terminal from state row
  -- ================================================================
  IF v_state.is_terminal = TRUE THEN
    RAISE EXCEPTION 'TERMINAL_STATUS: Cannot perform actions on application in terminal status (outcome=%)', v_state.outcome_type
      USING ERRCODE = 'P0001';
  END IF;

  -- ================================================================
  -- STEP 3: Get current stage details
  -- ================================================================
  SELECT * INTO v_current_stage
  FROM pipeline_stages
  WHERE id = v_state.current_stage_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Current stage not found (data integrity error)'
      USING ERRCODE = 'P0004';
  END IF;

  -- ================================================================
  -- STEP 4: Validate action — scoped to stage_id (not stage_type)
  -- ================================================================
  SELECT * INTO v_action
  FROM tenant_stage_actions
  WHERE tenant_id = v_state.tenant_id
    AND stage_id = v_state.current_stage_id
    AND action_code = p_action_code
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_ACTION: Action "%" is not available for stage "%"', p_action_code, v_current_stage.stage_name
      USING ERRCODE = 'P0007';
  END IF;

  -- ================================================================
  -- STEP 5: Capability check — derived from user_id, not passed role
  -- ================================================================
  SELECT EXISTS (
    SELECT 1 FROM role_capabilities rc
    JOIN user_profiles up ON up.tenant_id = rc.tenant_id AND up.role = rc.role_name
    WHERE up.id = p_user_id
      AND rc.tenant_id = v_state.tenant_id
      AND rc.capability = v_action.required_capability
  ) INTO v_has_capability;

  IF NOT v_has_capability THEN
    RAISE EXCEPTION 'FORBIDDEN: User does not have capability "%" required for action "%"', v_action.required_capability, p_action_code
      USING ERRCODE = 'P0008';
  END IF;

  -- ================================================================
  -- STEP 6: Notes gate
  -- ================================================================
  IF v_action.requires_notes = TRUE AND (p_notes IS NULL OR TRIM(p_notes) = '') THEN
    RAISE EXCEPTION 'VALIDATION: Notes are required for action "%"', p_action_code
      USING ERRCODE = 'P0009';
  END IF;

  -- ================================================================
  -- STEP 7: Feedback gate
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
  -- STEP 8: HOLD/ACTIVATE guards — using outcome_type from state row
  -- ================================================================
  IF v_action.outcome_type = 'HOLD' AND v_state.outcome_type != 'ACTIVE' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot hold application that is not ACTIVE (current outcome: %)', v_state.outcome_type
      USING ERRCODE = 'P0007';
  END IF;

  IF v_action.outcome_type = 'ACTIVE' AND v_state.outcome_type != 'HOLD' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot reactivate application that is not on HOLD (current outcome: %)', v_state.outcome_type
      USING ERRCODE = 'P0007';
  END IF;

  -- ================================================================
  -- STEP 9: Compute next stage, outcome, and status
  -- ================================================================
  v_new_stage_id := v_state.current_stage_id;
  v_new_outcome := v_state.outcome_type;
  v_new_is_terminal := v_action.is_terminal;
  v_new_status := v_state.status;

  -- Stage advancement
  IF v_action.moves_to_next_stage = TRUE THEN
    SELECT * INTO v_next_stage
    FROM pipeline_stages
    WHERE pipeline_id = v_state.pipeline_id
      AND order_index = v_current_stage.order_index + 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'INVALID_ACTION: At last stage — use a terminal action instead'
        USING ERRCODE = 'P0007';
    END IF;

    v_new_stage_id := v_next_stage.id;
  END IF;

  -- Outcome resolution (outcome_type is primary, status is derived)
  IF v_action.outcome_type IS NOT NULL THEN
    v_new_outcome := v_action.outcome_type;

    -- Derive presentation status from outcome_type
    SELECT status_code INTO v_new_status
    FROM tenant_application_statuses
    WHERE tenant_id = v_state.tenant_id
      AND outcome_type = v_action.outcome_type
      AND is_terminal = v_action.is_terminal
      AND is_active = TRUE
    ORDER BY sort_order
    LIMIT 1;

    IF v_new_status IS NULL THEN
      RAISE EXCEPTION 'INVALID_STATUS: No status configured for outcome=% terminal=%', v_action.outcome_type, v_action.is_terminal
        USING ERRCODE = 'P0006';
    END IF;
  END IF;

  -- ================================================================
  -- STEP 10: Idempotency check
  -- ================================================================
  v_event_hash := md5(
    p_application_id::text || p_action_code ||
    v_state.current_stage_id::text || v_new_stage_id::text ||
    COALESCE(v_new_outcome, 'null') || COALESCE(v_new_status, 'null')
  );

  IF v_new_stage_id = v_state.current_stage_id
     AND v_new_outcome = v_state.outcome_type
     AND v_new_is_terminal = v_state.is_terminal
     AND COALESCE(v_new_status, '') = COALESCE(v_state.status, '') THEN
    v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
                 v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at,
                 v_state.outcome_type, v_state.is_terminal);
    RETURN v_result;
  END IF;

  -- ================================================================
  -- STEP 11: Execute the mutation
  -- ================================================================
  UPDATE application_pipeline_state
  SET
    current_stage_id = v_new_stage_id,
    outcome_type = v_new_outcome,
    is_terminal = v_new_is_terminal,
    status = COALESCE(v_new_status, status),
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
  -- STEP 13: Log and return (with outcome_type + is_terminal)
  -- ================================================================
  RAISE LOG 'ACTION_ENGINE_V2: app=% action=% from_stage=% to_stage=% outcome=% terminal=%',
    p_application_id, p_action_code, v_current_stage.id, v_new_stage_id, v_new_outcome, v_new_is_terminal;

  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at,
               v_state.outcome_type, v_state.is_terminal);
  RETURN v_result;
END;
$$;
