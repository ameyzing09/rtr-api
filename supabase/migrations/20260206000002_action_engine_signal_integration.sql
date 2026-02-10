-- ============================================================================
-- ACTION ENGINE V2 SIGNAL INTEGRATION
-- ============================================================================
-- Adds signal conditions to tenant_stage_actions and modifies execute_action_v2
-- to enforce signal gates and log to action_execution_log.
--
-- Part 1: Add signal_conditions column to tenant_stage_actions
-- Part 2: Update execute_action_v2 to include signal gates + audit logging
-- ============================================================================

-- ============================================================================
-- PART 1: Add signal_conditions column to tenant_stage_actions
-- ============================================================================

ALTER TABLE tenant_stage_actions
ADD COLUMN signal_conditions JSONB DEFAULT NULL;

COMMENT ON COLUMN tenant_stage_actions.signal_conditions IS
  'JSONB signal conditions with explicit missing-signal behavior. Example:
   {
     "logic": "ALL",
     "conditions": [
       { "signal": "INTERVIEW_GO", "operator": ">=", "value": 2, "on_missing": "BLOCK" },
       { "signal": "TECH_PASS", "operator": "=", "value": true, "on_missing": "BLOCK" },
       { "signal": "CULTURE_FIT", "operator": "=", "value": true, "on_missing": "WARN" }
     ]
   }
   on_missing semantics:
     "BLOCK" - Missing signal = condition fails (action blocked)
     "ALLOW" - Missing signal = condition passes (proceed anyway)
     "WARN"  - Missing signal = condition passes but logs warning + requires note';

-- ============================================================================
-- PART 2: Update execute_action_v2 RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION execute_action_v2(
  p_application_id UUID,
  p_tenant_id UUID,
  p_user_id UUID,
  p_action_code TEXT,
  p_notes TEXT DEFAULT NULL,
  -- NEW: Accountability chain parameters
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
  v_feedback_count INT;
  -- NEW: Signal-related variables
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
  'Execute an action on an application with signal condition gates and comprehensive audit logging.
   Added parameters: p_override_reason, p_reviewed_by, p_approved_by for accountability chain.
   Signal snapshot captured at decision time for audit trail.';

-- ============================================================================
-- Helper RPC: Get signals for action condition display
-- ============================================================================

CREATE OR REPLACE FUNCTION get_action_signal_status(
  p_application_id UUID,
  p_action_code TEXT,
  p_stage_id UUID,
  p_tenant_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_action tenant_stage_actions%ROWTYPE;
  v_conditions JSONB;
  v_result JSONB := '{"signalsMet": true, "conditions": []}'::jsonb;
  v_condition JSONB;
  v_signal_key TEXT;
  v_operator TEXT;
  v_expected_value TEXT;
  v_on_missing TEXT;
  v_actual_text TEXT;
  v_actual_numeric NUMERIC;
  v_actual_boolean BOOLEAN;
  v_signal_type TEXT;
  v_signal_found BOOLEAN;
  v_condition_met BOOLEAN;
  v_condition_result JSONB;
  v_all_met BOOLEAN := TRUE;
  v_any_met BOOLEAN := FALSE;
  v_logic TEXT;
BEGIN
  -- Get action definition
  SELECT * INTO v_action
  FROM tenant_stage_actions
  WHERE tenant_id = p_tenant_id
    AND stage_id = p_stage_id
    AND action_code = p_action_code
    AND is_active = TRUE;

  IF NOT FOUND OR v_action.signal_conditions IS NULL THEN
    RETURN v_result;
  END IF;

  v_conditions := v_action.signal_conditions->'conditions';
  v_logic := COALESCE(v_action.signal_conditions->>'logic', 'ALL');

  IF v_conditions IS NULL THEN
    RETURN v_result;
  END IF;

  -- Evaluate each condition
  FOR v_condition IN SELECT * FROM jsonb_array_elements(v_conditions) LOOP
    v_signal_key := v_condition->>'signal';
    v_operator := v_condition->>'operator';
    v_expected_value := v_condition->>'value';
    v_on_missing := COALESCE(v_condition->>'on_missing', 'BLOCK');

    -- Query current signal value
    SELECT signal_type, signal_value_text, signal_value_numeric, signal_value_boolean, TRUE
    INTO v_signal_type, v_actual_text, v_actual_numeric, v_actual_boolean, v_signal_found
    FROM application_signals_latest
    WHERE application_id = p_application_id
      AND signal_key = v_signal_key;

    v_signal_found := COALESCE(v_signal_found, FALSE);

    IF NOT v_signal_found THEN
      CASE v_on_missing
        WHEN 'BLOCK' THEN
          v_condition_met := FALSE;
          v_condition_result := jsonb_build_object(
            'signal', v_signal_key, 'operator', v_operator, 'value', v_expected_value,
            'onMissing', v_on_missing, 'currentValue', NULL,
            'met', FALSE, 'reason', 'SIGNAL_MISSING'
          );
        WHEN 'ALLOW' THEN
          v_condition_met := TRUE;
          v_condition_result := jsonb_build_object(
            'signal', v_signal_key, 'operator', v_operator, 'value', v_expected_value,
            'onMissing', v_on_missing, 'currentValue', NULL,
            'met', TRUE, 'reason', 'MISSING_ALLOWED'
          );
        WHEN 'WARN' THEN
          v_condition_met := TRUE;
          v_condition_result := jsonb_build_object(
            'signal', v_signal_key, 'operator', v_operator, 'value', v_expected_value,
            'onMissing', v_on_missing, 'currentValue', NULL,
            'met', TRUE, 'warning', TRUE, 'reason', 'MISSING_WITH_WARNING'
          );
        ELSE
          v_condition_met := FALSE;
          v_condition_result := jsonb_build_object(
            'signal', v_signal_key, 'operator', v_operator, 'value', v_expected_value,
            'onMissing', v_on_missing, 'currentValue', NULL,
            'met', FALSE, 'reason', 'SIGNAL_MISSING'
          );
      END CASE;
    ELSE
      v_condition_met := evaluate_signal_condition(
        v_signal_key, v_actual_text, v_actual_numeric, v_actual_boolean,
        v_signal_type, v_operator, v_expected_value
      );
      v_condition_result := jsonb_build_object(
        'signal', v_signal_key, 'operator', v_operator, 'value', v_expected_value,
        'onMissing', v_on_missing,
        'currentValue', COALESCE(v_actual_boolean::TEXT, v_actual_numeric::TEXT, v_actual_text),
        'met', v_condition_met
      );
    END IF;

    v_result := jsonb_set(v_result, '{conditions}',
      COALESCE(v_result->'conditions', '[]'::jsonb) || v_condition_result);

    IF v_condition_met THEN
      v_any_met := TRUE;
    ELSE
      v_all_met := FALSE;
    END IF;
  END LOOP;

  -- Determine if signals are met based on logic
  IF v_logic = 'ALL' THEN
    v_result := jsonb_set(v_result, '{signalsMet}', to_jsonb(v_all_met));
  ELSE
    v_result := jsonb_set(v_result, '{signalsMet}', to_jsonb(v_any_met));
  END IF;

  v_result := jsonb_set(v_result, '{logic}', to_jsonb(v_logic));

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION get_action_signal_status IS
  'Returns signal condition status for an action including current values and met/unmet status';
