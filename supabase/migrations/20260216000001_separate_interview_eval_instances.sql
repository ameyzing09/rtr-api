-- ============================================================================
-- SEPARATE INTERVIEW-ROUND EVAL INSTANCES FROM STAGE-LEVEL EVAL INSTANCES
-- ============================================================================
-- Problem: evaluation_instances has a unique constraint
-- (tenant_id, application_id, template_id, stage_id). Interview rounds share
-- eval instances with stage-level evaluations, causing:
--   1. Stage gate pollution — interview evals leak into execute_action_v2()
--   2. Shared instances — multiple rounds with same template share one instance
--   3. No clean separation between stage-level and round-level evaluations
--
-- Fix: add interview_round_id, replace the single unique constraint with two
-- partial unique indexes, and filter all stage-level queries by
-- interview_round_id IS NULL.
--
-- Internal order:
--   1. Add column + index
--   2. Pre-check for responses on shared instances (fail-fast)
--   3. Lock table + drop old unique constraint (must precede split)
--   4. Split shared instances + derive participants from interviewer_assignments
--   5. Set interview_round_id on 1:1 round instances
--   6. Create partial unique indexes
--   7. Replace ensure_stage_evaluations()
--   8. Replace execute_action_v2() with interview_round_id IS NULL filter
-- ============================================================================

-- ============================================================================
-- STEP 1: Add interview_round_id column + filtered index
-- ============================================================================

ALTER TABLE evaluation_instances
  ADD COLUMN interview_round_id UUID NULL;

CREATE INDEX idx_evaluation_instances_round
  ON evaluation_instances(interview_round_id)
  WHERE interview_round_id IS NOT NULL;

-- ============================================================================
-- STEP 2: Pre-check — fail if shared instances have responses
-- ============================================================================

DO $$
DECLARE v_cnt INT;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM evaluation_instances ei
  WHERE (SELECT count(*) FROM interview_rounds ir WHERE ir.evaluation_instance_id = ei.id) > 1
    AND EXISTS (
      SELECT 1 FROM evaluation_participants ep
      JOIN evaluation_responses er ON er.participant_id = ep.id
      WHERE ep.evaluation_id = ei.id
    );
  IF v_cnt > 0 THEN
    RAISE EXCEPTION 'MIGRATION_BLOCKED: % shared instances have responses; wipe dev data first', v_cnt;
  END IF;
END;
$$;

-- ============================================================================
-- STEP 3: Lock table + drop old constraint (must happen before split)
-- ============================================================================
-- Cloned instances share (tenant, app, template, stage) with the original,
-- so the old unique constraint must be removed first.

LOCK TABLE evaluation_instances IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE evaluation_instances
  DROP CONSTRAINT uq_evaluation_instances_app_template_stage;

-- ============================================================================
-- STEP 4: Split shared instances
-- ============================================================================
-- For each evaluation_instance referenced by >1 interview_round:
--   - Keep original for lowest-sequence round
--   - For each additional round: clone instance, derive participants from
--     interviewer_assignments, rewire round's evaluation_instance_id

DO $$
DECLARE
  v_shared RECORD;
  v_round RECORD;
  v_first BOOLEAN;
  v_new_instance_id UUID;
BEGIN
  FOR v_shared IN
    SELECT ei.id AS instance_id,
           ei.tenant_id,
           ei.application_id,
           ei.template_id,
           ei.stage_id,
           ei.status,
           ei.created_by
    FROM evaluation_instances ei
    WHERE (SELECT count(*) FROM interview_rounds ir WHERE ir.evaluation_instance_id = ei.id) > 1
  LOOP
    v_first := TRUE;

    FOR v_round IN
      SELECT ir.id AS round_id, ir.sequence
      FROM interview_rounds ir
      WHERE ir.evaluation_instance_id = v_shared.instance_id
      ORDER BY ir.sequence
    LOOP
      IF v_first THEN
        -- Keep original for lowest-sequence round
        v_first := FALSE;
        CONTINUE;
      END IF;

      -- Clone the eval instance
      v_new_instance_id := gen_random_uuid();

      INSERT INTO evaluation_instances (
        id, tenant_id, application_id, template_id, stage_id, status, created_by
      ) VALUES (
        v_new_instance_id,
        v_shared.tenant_id,
        v_shared.application_id,
        v_shared.template_id,
        v_shared.stage_id,
        v_shared.status,
        v_shared.created_by
      );

      -- Derive participants from interviewer_assignments for this round
      INSERT INTO evaluation_participants (tenant_id, evaluation_id, user_id, status)
      SELECT ia.tenant_id, v_new_instance_id, ia.user_id, 'PENDING'
      FROM interviewer_assignments ia
      WHERE ia.round_id = v_round.round_id
      ON CONFLICT (evaluation_id, user_id) DO NOTHING;

      -- Rewire round to the new cloned instance
      UPDATE interview_rounds
      SET evaluation_instance_id = v_new_instance_id
      WHERE id = v_round.round_id;
    END LOOP;
  END LOOP;
END;
$$;

-- ============================================================================
-- STEP 5: Set interview_round_id on all round-linked instances (now 1:1)
-- ============================================================================

UPDATE evaluation_instances ei
SET interview_round_id = ir.id
FROM interview_rounds ir
WHERE ir.evaluation_instance_id = ei.id
  AND ei.interview_round_id IS NULL;

-- ============================================================================
-- STEP 6: Create partial unique indexes
-- ============================================================================

-- Stage-level: one per (tenant, app, template, stage) where no round
CREATE UNIQUE INDEX uq_eval_instances_stage_level
  ON evaluation_instances (tenant_id, application_id, template_id, stage_id)
  WHERE interview_round_id IS NULL;

-- Round-level: one eval instance per round
CREATE UNIQUE INDEX uq_eval_instances_round_level
  ON evaluation_instances (interview_round_id)
  WHERE interview_round_id IS NOT NULL;

-- ============================================================================
-- STEP 7: Replace ensure_stage_evaluations() — updated ON CONFLICT + HR lookup
-- ============================================================================

CREATE OR REPLACE FUNCTION ensure_stage_evaluations(
  p_tenant_id UUID,
  p_application_id UUID,
  p_stage_id UUID
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count INT := 0;
  v_rec RECORD;
  v_is_hr_stage BOOLEAN := false;
  v_hr_participant_id UUID;
  v_instance_id UUID;
BEGIN
  -- Check if this is an HR-conducted stage (once, before the loop)
  SELECT UPPER(ps.conducted_by) = 'HR' INTO v_is_hr_stage
  FROM pipeline_stages ps
  WHERE ps.id = p_stage_id;

  -- Resolve participant once for all evaluations on this stage
  IF v_is_hr_stage THEN
    v_hr_participant_id := resolve_hr_participant(p_tenant_id, p_application_id);
  END IF;

  FOR v_rec IN
    SELECT se.evaluation_template_id, se.execution_order
    FROM stage_evaluations se
    WHERE se.stage_id = p_stage_id
      AND se.tenant_id = p_tenant_id
      AND se.auto_create = true
      AND se.is_active = true
    ORDER BY se.execution_order
  LOOP
    INSERT INTO evaluation_instances (
      tenant_id, application_id, template_id, stage_id, status
    ) VALUES (
      p_tenant_id, p_application_id, v_rec.evaluation_template_id, p_stage_id, 'PENDING'
    )
    ON CONFLICT (tenant_id, application_id, template_id, stage_id)
      WHERE interview_round_id IS NULL
      DO NOTHING;

    IF FOUND THEN
      v_count := v_count + 1;
    END IF;

    -- Auto-add participant for HR stages
    IF v_is_hr_stage AND v_hr_participant_id IS NOT NULL THEN
      -- Get instance ID (whether just-inserted or pre-existing)
      SELECT ei.id INTO v_instance_id
      FROM evaluation_instances ei
      WHERE ei.tenant_id = p_tenant_id
        AND ei.application_id = p_application_id
        AND ei.template_id = v_rec.evaluation_template_id
        AND ei.stage_id = p_stage_id
        AND ei.interview_round_id IS NULL;

      IF v_instance_id IS NOT NULL THEN
        INSERT INTO evaluation_participants (
          tenant_id, evaluation_id, user_id, status
        ) VALUES (
          p_tenant_id, v_instance_id, v_hr_participant_id, 'PENDING'
        )
        ON CONFLICT (evaluation_id, user_id) DO NOTHING;
      END IF;
    END IF;
  END LOOP;

  RAISE LOG 'STAGE_EVAL_AUTO_CREATE: app=% stage=% created=%', p_application_id, p_stage_id, v_count;
  RETURN v_count;
END;
$$;

-- ============================================================================
-- STEP 8: Replace execute_action_v2() — add interview_round_id IS NULL filter
-- ============================================================================

CREATE OR REPLACE FUNCTION execute_action_v2(
  p_application_id UUID,
  p_tenant_id UUID,
  p_user_id UUID,
  p_action_code TEXT,
  p_notes TEXT DEFAULT NULL,
  p_override_reason TEXT DEFAULT NULL,
  p_reviewed_by UUID DEFAULT NULL,
  p_approved_by UUID DEFAULT NULL
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
  v_incomplete_evals TEXT[];
  v_incomplete_count INT;
  -- Signal-related variables
  v_signal_snapshot JSONB := '{}';
  v_conditions_evaluated JSONB := '[]';
  v_has_warnings BOOLEAN := FALSE;
  v_requires_note_for_warning BOOLEAN := FALSE;
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
  -- STEP 7: Evaluation completion gate (replaces legacy feedback gate)
  -- Fail-open: no required stage_evaluations = no block.
  -- Only checks stage-level instances (interview_round_id IS NULL).
  -- ================================================================
  SELECT
    COALESCE(array_agg(et.name ORDER BY se.execution_order), '{}'),
    COUNT(*)
  INTO v_incomplete_evals, v_incomplete_count
  FROM stage_evaluations se
  JOIN evaluation_templates et ON et.id = se.evaluation_template_id
  LEFT JOIN evaluation_instances ei
    ON ei.template_id = se.evaluation_template_id
    AND ei.stage_id = se.stage_id
    AND ei.application_id = p_application_id
    AND ei.tenant_id = p_tenant_id
    AND ei.status = 'COMPLETED'
    AND ei.interview_round_id IS NULL
  WHERE se.stage_id = v_state.current_stage_id
    AND se.required = true
    AND se.is_active = true
    AND se.tenant_id = p_tenant_id
    AND ei.id IS NULL;  -- no completed stage-level instance

  IF v_incomplete_count > 0 THEN
    RAISE EXCEPTION 'EVALUATIONS_INCOMPLETE: % required evaluation(s) not completed for stage "%": %',
      v_incomplete_count, v_current_stage.stage_name,
      array_to_string(v_incomplete_evals, ', ')
      USING ERRCODE = 'P0014';
  END IF;

  -- ================================================================
  -- STEP 7.5: Signal conditions gate + snapshot capture
  -- ================================================================
  -- CONSTRAINT: Signals are READ-ONLY at action time.
  -- Signal generation MUST NOT depend on action availability.
  -- This prevents cyclic dependencies.
  -- ================================================================

  -- Always capture signal snapshot for audit (even if no conditions)
  SELECT COALESCE(
    jsonb_object_agg(
      signal_key,
      jsonb_build_object(
        'value', COALESCE(signal_value_boolean::TEXT, signal_value_numeric::TEXT, signal_value_text),
        'type', signal_type,
        'set_at', set_at,
        'set_by', set_by,
        'source_type', source_type,
        'source_id', source_id
      )
    ),
    '{}'::jsonb
  ) INTO v_signal_snapshot
  FROM application_signals_latest
  WHERE application_id = p_application_id;

  -- Evaluate signal conditions if defined
  IF v_action.signal_conditions IS NOT NULL THEN
    DECLARE
      v_conditions JSONB := v_action.signal_conditions->'conditions';
      v_logic TEXT := COALESCE(v_action.signal_conditions->>'logic', 'ALL');
      v_condition JSONB;
      v_signal_key TEXT;
      v_signal_type TEXT;
      v_operator TEXT;
      v_expected_value TEXT;
      v_on_missing TEXT;
      v_actual_text TEXT;
      v_actual_numeric NUMERIC;
      v_actual_boolean BOOLEAN;
      v_signal_found BOOLEAN;
      v_condition_met BOOLEAN;
      v_condition_result JSONB;
      v_all_met BOOLEAN := TRUE;
      v_any_met BOOLEAN := FALSE;
      v_failed_conditions TEXT[] := '{}';
    BEGIN
      IF v_conditions IS NOT NULL THEN
        FOR v_condition IN SELECT * FROM jsonb_array_elements(v_conditions) LOOP
          v_signal_key := v_condition->>'signal';
          v_operator := v_condition->>'operator';
          v_expected_value := v_condition->>'value';
          v_on_missing := COALESCE(v_condition->>'on_missing', 'BLOCK');  -- Default: BLOCK

          -- Query the LATEST view for current signal values
          SELECT signal_type, signal_value_text, signal_value_numeric, signal_value_boolean, TRUE
          INTO v_signal_type, v_actual_text, v_actual_numeric, v_actual_boolean, v_signal_found
          FROM application_signals_latest
          WHERE application_id = p_application_id
            AND signal_key = v_signal_key;

          v_signal_found := COALESCE(v_signal_found, FALSE);

          -- Handle missing signal with explicit semantics
          IF NOT v_signal_found THEN
            CASE v_on_missing
              WHEN 'BLOCK' THEN
                v_condition_met := FALSE;
                v_condition_result := jsonb_build_object(
                  'signal', v_signal_key, 'operator', v_operator, 'expected', v_expected_value,
                  'actual', NULL, 'on_missing', v_on_missing, 'met', FALSE, 'reason', 'SIGNAL_MISSING'
                );
              WHEN 'ALLOW' THEN
                v_condition_met := TRUE;
                v_condition_result := jsonb_build_object(
                  'signal', v_signal_key, 'operator', v_operator, 'expected', v_expected_value,
                  'actual', NULL, 'on_missing', v_on_missing, 'met', TRUE, 'reason', 'MISSING_ALLOWED'
                );
              WHEN 'WARN' THEN
                v_condition_met := TRUE;
                v_has_warnings := TRUE;
                v_requires_note_for_warning := TRUE;
                v_condition_result := jsonb_build_object(
                  'signal', v_signal_key, 'operator', v_operator, 'expected', v_expected_value,
                  'actual', NULL, 'on_missing', v_on_missing, 'met', TRUE, 'warning', TRUE,
                  'reason', 'MISSING_WITH_WARNING'
                );
                RAISE WARNING 'Signal "%" missing for action "%", proceeding with warning', v_signal_key, p_action_code;
              ELSE
                -- Unknown on_missing value, default to BLOCK
                v_condition_met := FALSE;
                v_condition_result := jsonb_build_object(
                  'signal', v_signal_key, 'operator', v_operator, 'expected', v_expected_value,
                  'actual', NULL, 'on_missing', v_on_missing, 'met', FALSE, 'reason', 'SIGNAL_MISSING'
                );
            END CASE;
          ELSE
            -- Signal exists - evaluate normally
            v_condition_met := evaluate_signal_condition(
              v_signal_key, v_actual_text, v_actual_numeric, v_actual_boolean,
              v_signal_type, v_operator, v_expected_value
            );
            v_condition_result := jsonb_build_object(
              'signal', v_signal_key, 'operator', v_operator, 'expected', v_expected_value,
              'actual', COALESCE(v_actual_boolean::TEXT, v_actual_numeric::TEXT, v_actual_text),
              'met', v_condition_met
            );
          END IF;

          -- Accumulate results
          v_conditions_evaluated := v_conditions_evaluated || v_condition_result;

          IF v_condition_met THEN
            v_any_met := TRUE;
          ELSE
            v_all_met := FALSE;
            v_failed_conditions := array_append(v_failed_conditions,
              format('%s %s %s (actual: %s)',
                v_signal_key, v_operator, v_expected_value,
                COALESCE(v_actual_text, v_actual_numeric::TEXT, v_actual_boolean::TEXT, 'MISSING')
              )
            );
          END IF;
        END LOOP;

        -- WARN conditions require a note
        IF v_requires_note_for_warning AND (p_notes IS NULL OR TRIM(p_notes) = '') THEN
          RAISE EXCEPTION 'VALIDATION: Note required when proceeding with missing signal warnings'
            USING ERRCODE = 'P0009';
        END IF;

        -- Apply logic with detailed error message
        IF v_logic = 'ALL' AND NOT v_all_met THEN
          RAISE EXCEPTION 'SIGNALS_NOT_MET: Required signal conditions not satisfied for action "%". Failed: %',
            p_action_code, array_to_string(v_failed_conditions, ', ')
            USING ERRCODE = 'P0012';
        END IF;

        IF v_logic = 'ANY' AND NOT v_any_met THEN
          RAISE EXCEPTION 'SIGNALS_NOT_MET: At least one signal condition must be met for action "%". Checked: %',
            p_action_code, array_to_string(v_failed_conditions, ', ')
            USING ERRCODE = 'P0012';
        END IF;
      END IF;
    END;
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
  -- STEP 12.5: Write to action_execution_log (immutable audit record)
  -- ================================================================
  INSERT INTO action_execution_log (
    tenant_id,
    application_id,
    action_code,
    stage_id,
    executed_by,
    executed_at,
    signal_snapshot,
    conditions_evaluated,
    decision_note,
    override_reason,
    reviewed_by,
    approved_by,
    outcome_type,
    is_terminal,
    from_stage_id,
    to_stage_id
  ) VALUES (
    p_tenant_id,
    p_application_id,
    p_action_code,
    v_state.current_stage_id,
    p_user_id,
    NOW(),
    COALESCE(v_signal_snapshot, '{}'),
    COALESCE(v_conditions_evaluated, '[]'),
    p_notes,
    p_override_reason,
    p_reviewed_by,
    p_approved_by,
    v_new_outcome,
    v_new_is_terminal,
    v_current_stage.id,
    v_new_stage_id
  );

  -- ================================================================
  -- STEP 13: Log and return (with outcome_type + is_terminal)
  -- ================================================================
  RAISE LOG 'ACTION_ENGINE_V2: app=% action=% from_stage=% to_stage=% outcome=% terminal=% signals_met=%',
    p_application_id, p_action_code, v_current_stage.id, v_new_stage_id, v_new_outcome, v_new_is_terminal,
    CASE WHEN v_conditions_evaluated = '[]'::jsonb THEN 'N/A' ELSE 'YES' END;

  v_result := (v_state.id, v_state.application_id, v_state.job_id, v_state.pipeline_id,
               v_state.current_stage_id, v_state.status, v_state.entered_stage_at, v_state.updated_at,
               v_state.outcome_type, v_state.is_terminal);
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION execute_action_v2 IS
  'Execute an action on an application with evaluation completion gate and signal condition gates.
   Step 7 now checks only stage-level evaluation_instances (interview_round_id IS NULL).
   Interview-round evaluations are excluded from the stage gate.';
