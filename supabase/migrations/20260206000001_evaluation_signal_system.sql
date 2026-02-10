-- ============================================================================
-- EVALUATION FRAMEWORK + SIGNAL SYSTEM MIGRATION
-- ============================================================================
-- Mental Model: Evaluation -> Emits Signals -> Action Engine consumes signals -> HR executes action
--
-- Part 1: Evaluation templates (HR-defined, versioned)
-- Part 2: Evaluation instances (per application)
-- Part 3: Evaluation participants (who evaluates)
-- Part 4: Evaluation responses (submitted feedback per participant)
-- Part 5: Application signals (APPEND-ONLY signal history)
-- Part 6: Action execution log (signal snapshots + accountability)
-- Part 7: Signal condition helper function
-- Part 8: Signal aggregation function
-- Part 9: Evaluation completion function
-- Part 10: RLS policies
-- Part 11: Seed functions + triggers
-- ============================================================================

-- ============================================================================
-- PART 1: Evaluation Templates (HR-defined, versioned)
-- ============================================================================

CREATE TABLE evaluation_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,

  -- Versioning (immutable once referenced by instances)
  version INTEGER NOT NULL DEFAULT 1,
  is_latest BOOLEAN NOT NULL DEFAULT TRUE,
  superseded_by UUID REFERENCES evaluation_templates(id),

  -- Configuration
  participant_type VARCHAR(50) NOT NULL DEFAULT 'SINGLE'
    CHECK (participant_type IN ('SINGLE', 'PANEL', 'SEQUENTIAL')),

  -- Signal definitions with PER-SIGNAL aggregation
  -- Example: [
  --   { "key": "TECH_PASS", "type": "boolean", "label": "Technically qualified?", "aggregation": "MAJORITY" },
  --   { "key": "TECH_SCORE", "type": "integer", "label": "Technical Score (1-5)", "min": 1, "max": 5, "aggregation": "AVERAGE" },
  --   { "key": "RISK_FLAG", "type": "boolean", "label": "Any concerns?", "aggregation": "ANY" },
  --   { "key": "NOTES", "type": "text", "label": "Notes", "aggregation": null }  -- No aggregation for text
  -- ]
  signal_schema JSONB NOT NULL DEFAULT '[]',

  -- Default aggregation (fallback if signal doesn't specify)
  default_aggregation VARCHAR(50) DEFAULT 'MAJORITY'
    CHECK (default_aggregation IN ('MAJORITY', 'UNANIMOUS', 'ANY', 'AVERAGE')),

  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(tenant_id, name, version)
);

CREATE INDEX idx_evaluation_templates_tenant ON evaluation_templates(tenant_id);
CREATE INDEX idx_evaluation_templates_latest ON evaluation_templates(tenant_id, name) WHERE is_latest = TRUE;

COMMENT ON TABLE evaluation_templates IS 'HR-defined evaluation templates with per-signal aggregation rules';
COMMENT ON COLUMN evaluation_templates.signal_schema IS 'JSON array of signal definitions with per-signal aggregation: MAJORITY, UNANIMOUS, ANY, AVERAGE, or null (no aggregation)';

-- ============================================================================
-- PART 2: Evaluation Instances (per application, optionally tied to stage)
-- ============================================================================

CREATE TABLE evaluation_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
  template_id UUID NOT NULL REFERENCES evaluation_templates(id) ON DELETE RESTRICT,

  -- Optional stage binding (evaluation can exist independent of stage)
  stage_id UUID REFERENCES pipeline_stages(id) ON DELETE SET NULL,

  -- Status
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),

  -- Scheduling (optional, for interview-type evaluations)
  scheduled_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,

  -- Force complete metadata
  force_completed BOOLEAN DEFAULT FALSE,
  force_complete_note TEXT,
  force_completed_by UUID REFERENCES auth.users(id),

  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_evaluation_instances_tenant ON evaluation_instances(tenant_id);
CREATE INDEX idx_evaluation_instances_application ON evaluation_instances(application_id);
CREATE INDEX idx_evaluation_instances_stage ON evaluation_instances(stage_id);
CREATE INDEX idx_evaluation_instances_status ON evaluation_instances(status);
CREATE INDEX idx_evaluation_instances_template ON evaluation_instances(template_id);

COMMENT ON TABLE evaluation_instances IS 'Evaluation instances per application, optionally bound to a pipeline stage';

-- ============================================================================
-- PART 3: Evaluation Participants (who evaluates)
-- ============================================================================

CREATE TABLE evaluation_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  evaluation_id UUID NOT NULL REFERENCES evaluation_instances(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),

  status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'SUBMITTED', 'DECLINED')),

  submitted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(evaluation_id, user_id)
);

CREATE INDEX idx_evaluation_participants_user ON evaluation_participants(user_id);
CREATE INDEX idx_evaluation_participants_evaluation ON evaluation_participants(evaluation_id);

COMMENT ON TABLE evaluation_participants IS 'Participants assigned to evaluate in an evaluation instance';

-- ============================================================================
-- PART 4: Evaluation Responses (submitted feedback per participant)
-- ============================================================================

CREATE TABLE evaluation_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  participant_id UUID NOT NULL REFERENCES evaluation_participants(id) ON DELETE CASCADE,

  -- Raw response matching template's signal_schema
  -- Example: { "GO": true, "TECH_SCORE": 4, "NOTES": "Strong candidate" }
  response_data JSONB NOT NULL,

  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(participant_id)  -- One response per participant, immutable
);

CREATE INDEX idx_evaluation_responses_participant ON evaluation_responses(participant_id);

COMMENT ON TABLE evaluation_responses IS 'Immutable responses submitted by evaluation participants';
COMMENT ON COLUMN evaluation_responses.response_data IS 'Raw response data matching the templates signal_schema keys';

-- ============================================================================
-- PART 5: Application Signals (APPEND-ONLY signal history)
-- ============================================================================

CREATE TABLE application_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,

  signal_key VARCHAR(100) NOT NULL,
  signal_type VARCHAR(20) NOT NULL CHECK (signal_type IN ('boolean', 'integer', 'float', 'text')),

  -- Typed columns for safety (sparse usage OK)
  signal_value_text TEXT,
  signal_value_numeric NUMERIC,
  signal_value_boolean BOOLEAN,

  -- Source tracking (for audit)
  source_type VARCHAR(50) NOT NULL CHECK (source_type IN ('EVALUATION', 'MANUAL', 'SYSTEM')),
  source_id UUID,  -- evaluation_instance.id if from evaluation

  set_by UUID REFERENCES auth.users(id),
  set_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Versioning: signals are NEVER overwritten
  superseded_at TIMESTAMPTZ,  -- NULL means current/active
  superseded_by UUID REFERENCES application_signals(id)
);

CREATE INDEX idx_application_signals_application ON application_signals(application_id);
CREATE INDEX idx_application_signals_key ON application_signals(signal_key);
CREATE INDEX idx_application_signals_active ON application_signals(application_id, signal_key)
  WHERE superseded_at IS NULL;
CREATE INDEX idx_application_signals_source ON application_signals(source_type, source_id);

COMMENT ON TABLE application_signals IS 'Append-only signal history for applications. Old signals marked superseded_at when new value arrives.';
COMMENT ON COLUMN application_signals.superseded_at IS 'NULL means this is the current/active signal value';

-- View for Action Engine to query LATEST signals only
CREATE VIEW application_signals_latest AS
SELECT DISTINCT ON (application_id, signal_key) *
FROM application_signals
WHERE superseded_at IS NULL
ORDER BY application_id, signal_key, set_at DESC;

COMMENT ON VIEW application_signals_latest IS 'View showing only the latest (active) signal value per application+key';

-- ============================================================================
-- PART 6: Action Execution Log (signal snapshots + accountability)
-- ============================================================================

CREATE TABLE action_execution_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,

  -- What action was executed
  action_code VARCHAR(50) NOT NULL,
  stage_id UUID REFERENCES pipeline_stages(id),

  -- Who executed and when
  executed_by UUID NOT NULL REFERENCES auth.users(id),
  executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- SIGNAL SNAPSHOT at decision time (immutable audit record)
  -- Example: {
  --   "TECH_PASS": { "value": true, "type": "boolean", "set_at": "...", "set_by": "..." },
  --   "TECH_SCORE": { "value": 4.5, "type": "float", "set_at": "...", "set_by": "..." }
  -- }
  signal_snapshot JSONB NOT NULL DEFAULT '{}',

  -- Condition evaluation results
  -- Example: [
  --   { "signal": "TECH_PASS", "operator": "=", "expected": true, "actual": true, "met": true },
  --   { "signal": "CULTURE_FIT", "actual": null, "on_missing": "WARN", "met": true, "warning": true }
  -- ]
  conditions_evaluated JSONB DEFAULT '[]',

  -- Accountability chain
  decision_note TEXT,                              -- Why this action was taken
  override_reason TEXT,                            -- If rules were bypassed
  reviewed_by UUID REFERENCES auth.users(id),      -- Who reviewed feedback (if feedback-gated)
  approved_by UUID REFERENCES auth.users(id),      -- Who approved proceeding (if override)

  -- Outcome recorded
  outcome_type VARCHAR(20),
  is_terminal BOOLEAN,
  from_stage_id UUID REFERENCES pipeline_stages(id),
  to_stage_id UUID REFERENCES pipeline_stages(id)
);

CREATE INDEX idx_action_execution_log_application ON action_execution_log(application_id);
CREATE INDEX idx_action_execution_log_tenant ON action_execution_log(tenant_id);
CREATE INDEX idx_action_execution_log_executed_at ON action_execution_log(executed_at DESC);
CREATE INDEX idx_action_execution_log_executed_by ON action_execution_log(executed_by);
CREATE INDEX idx_action_execution_log_outcome ON action_execution_log(outcome_type);

COMMENT ON TABLE action_execution_log IS 'Immutable audit log of action executions with signal snapshots at decision time';
COMMENT ON COLUMN action_execution_log.signal_snapshot IS 'Snapshot of ALL signals at decision time for audit';
COMMENT ON COLUMN action_execution_log.conditions_evaluated IS 'Detailed result of each condition evaluation';
COMMENT ON COLUMN action_execution_log.override_reason IS 'Required explanation if rules were bypassed';

-- ============================================================================
-- PART 7: Signal Condition Helper Function
-- ============================================================================

CREATE OR REPLACE FUNCTION evaluate_signal_condition(
  p_signal_key TEXT,
  p_actual_text TEXT,
  p_actual_numeric NUMERIC,
  p_actual_boolean BOOLEAN,
  p_signal_type TEXT,
  p_operator TEXT,
  p_expected TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_result BOOLEAN;
BEGIN
  -- Handle missing signal
  IF p_actual_text IS NULL AND p_actual_numeric IS NULL AND p_actual_boolean IS NULL THEN
    RAISE WARNING 'Signal "%" not found for evaluation', p_signal_key;
    RETURN FALSE;
  END IF;

  -- Type-safe evaluation based on signal_type
  CASE p_signal_type
    WHEN 'boolean' THEN
      IF p_operator = '=' THEN
        v_result := p_actual_boolean = (p_expected::BOOLEAN);
      ELSIF p_operator = '!=' THEN
        v_result := p_actual_boolean != (p_expected::BOOLEAN);
      ELSE
        RAISE WARNING 'Invalid operator "%" for boolean signal "%"', p_operator, p_signal_key;
        RETURN FALSE;
      END IF;

    WHEN 'integer', 'float' THEN
      CASE p_operator
        WHEN '=' THEN v_result := p_actual_numeric = (p_expected::NUMERIC);
        WHEN '!=' THEN v_result := p_actual_numeric != (p_expected::NUMERIC);
        WHEN '>' THEN v_result := p_actual_numeric > (p_expected::NUMERIC);
        WHEN '>=' THEN v_result := p_actual_numeric >= (p_expected::NUMERIC);
        WHEN '<' THEN v_result := p_actual_numeric < (p_expected::NUMERIC);
        WHEN '<=' THEN v_result := p_actual_numeric <= (p_expected::NUMERIC);
        ELSE
          RAISE WARNING 'Invalid operator "%" for numeric signal "%"', p_operator, p_signal_key;
          RETURN FALSE;
      END CASE;

    WHEN 'text' THEN
      IF p_operator = '=' THEN
        v_result := p_actual_text = p_expected;
      ELSIF p_operator = '!=' THEN
        v_result := p_actual_text != p_expected;
      ELSE
        RAISE WARNING 'Invalid operator "%" for text signal "%"', p_operator, p_signal_key;
        RETURN FALSE;
      END IF;

    ELSE
      RAISE WARNING 'Unknown signal type "%" for signal "%"', p_signal_type, p_signal_key;
      RETURN FALSE;
  END CASE;

  RETURN COALESCE(v_result, FALSE);

EXCEPTION WHEN OTHERS THEN
  -- Log the error, don't silently swallow
  RAISE WARNING 'Signal evaluation failed for "%": % % % (error: %)',
    p_signal_key, p_actual_text, p_operator, p_expected, SQLERRM;
  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION evaluate_signal_condition IS 'Type-safe signal condition evaluation with logging';

-- ============================================================================
-- PART 8: Signal Aggregation Function
-- ============================================================================

CREATE OR REPLACE FUNCTION aggregate_evaluation_signals(
  p_evaluation_id UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_instance evaluation_instances%ROWTYPE;
  v_template evaluation_templates%ROWTYPE;
  v_signal_def JSONB;
  v_signal_key TEXT;
  v_signal_type TEXT;
  v_aggregation TEXT;
  v_value_boolean BOOLEAN;
  v_value_numeric NUMERIC;
  v_value_text TEXT;
  v_old_signal_id UUID;
  v_new_signal_id UUID;
BEGIN
  -- Get evaluation instance and template
  SELECT * INTO v_instance FROM evaluation_instances WHERE id = p_evaluation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Evaluation instance not found: %', p_evaluation_id;
  END IF;

  SELECT * INTO v_template FROM evaluation_templates WHERE id = v_instance.template_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Evaluation template not found: %', v_instance.template_id;
  END IF;

  -- For each signal in template
  FOR v_signal_def IN SELECT * FROM jsonb_array_elements(v_template.signal_schema) LOOP
    v_signal_key := v_signal_def->>'key';
    v_signal_type := v_signal_def->>'type';
    -- PER-SIGNAL aggregation, fallback to template default
    v_aggregation := COALESCE(v_signal_def->>'aggregation', v_template.default_aggregation);

    -- Reset values
    v_value_boolean := NULL;
    v_value_numeric := NULL;
    v_value_text := NULL;

    -- Skip text signals (no aggregation) or signals with null aggregation
    IF v_signal_type = 'text' OR v_aggregation IS NULL THEN
      CONTINUE;
    END IF;

    -- Aggregate based on PER-SIGNAL aggregation rule
    CASE v_aggregation
      WHEN 'MAJORITY' THEN
        IF v_signal_type = 'boolean' THEN
          SELECT COUNT(*) FILTER (WHERE (er.response_data->>v_signal_key)::boolean = true) >
                 COUNT(*) FILTER (WHERE (er.response_data->>v_signal_key)::boolean = false)
          INTO v_value_boolean
          FROM evaluation_responses er
          JOIN evaluation_participants ep ON ep.id = er.participant_id
          WHERE ep.evaluation_id = p_evaluation_id
            AND er.response_data ? v_signal_key;
        END IF;

      WHEN 'AVERAGE' THEN
        IF v_signal_type IN ('integer', 'float') THEN
          SELECT AVG((er.response_data->>v_signal_key)::NUMERIC)
          INTO v_value_numeric
          FROM evaluation_responses er
          JOIN evaluation_participants ep ON ep.id = er.participant_id
          WHERE ep.evaluation_id = p_evaluation_id
            AND er.response_data ? v_signal_key;
        END IF;

      WHEN 'ANY' THEN
        IF v_signal_type = 'boolean' THEN
          SELECT bool_or((er.response_data->>v_signal_key)::boolean)
          INTO v_value_boolean
          FROM evaluation_responses er
          JOIN evaluation_participants ep ON ep.id = er.participant_id
          WHERE ep.evaluation_id = p_evaluation_id
            AND er.response_data ? v_signal_key;
        END IF;

      WHEN 'UNANIMOUS' THEN
        IF v_signal_type = 'boolean' THEN
          SELECT bool_and((er.response_data->>v_signal_key)::boolean)
          INTO v_value_boolean
          FROM evaluation_responses er
          JOIN evaluation_participants ep ON ep.id = er.participant_id
          WHERE ep.evaluation_id = p_evaluation_id
            AND er.response_data ? v_signal_key;
        END IF;
    END CASE;

    -- Skip if no value was aggregated (no responses with this signal)
    IF v_value_boolean IS NULL AND v_value_numeric IS NULL AND v_value_text IS NULL THEN
      CONTINUE;
    END IF;

    -- Mark old signal as superseded (APPEND-ONLY)
    SELECT id INTO v_old_signal_id
    FROM application_signals
    WHERE application_id = v_instance.application_id
      AND signal_key = v_signal_key
      AND superseded_at IS NULL;

    IF v_old_signal_id IS NOT NULL THEN
      UPDATE application_signals
      SET superseded_at = NOW()
      WHERE id = v_old_signal_id;
    END IF;

    -- Insert new signal (never overwrite)
    INSERT INTO application_signals (
      tenant_id, application_id, signal_key, signal_type,
      signal_value_boolean, signal_value_numeric, signal_value_text,
      source_type, source_id, set_at
    ) VALUES (
      v_instance.tenant_id, v_instance.application_id,
      v_signal_key, v_signal_type,
      v_value_boolean, v_value_numeric, v_value_text,
      'EVALUATION', p_evaluation_id, NOW()
    )
    RETURNING id INTO v_new_signal_id;

    -- Link old signal to new one for audit trail
    IF v_old_signal_id IS NOT NULL THEN
      UPDATE application_signals
      SET superseded_by = v_new_signal_id
      WHERE id = v_old_signal_id;
    END IF;

    RAISE LOG 'SIGNAL_AGGREGATION: app=% signal=% type=% value=% from evaluation=%',
      v_instance.application_id, v_signal_key, v_signal_type,
      COALESCE(v_value_boolean::TEXT, v_value_numeric::TEXT, v_value_text),
      p_evaluation_id;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION aggregate_evaluation_signals IS 'Aggregates signals from evaluation responses using per-signal aggregation rules';

-- ============================================================================
-- PART 9: Evaluation Completion Function
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_evaluation(
  p_evaluation_id UUID,
  p_user_id UUID,
  p_force BOOLEAN DEFAULT FALSE,
  p_force_note TEXT DEFAULT NULL
) RETURNS evaluation_instances
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_instance evaluation_instances%ROWTYPE;
  v_template evaluation_templates%ROWTYPE;
  v_total_participants INT;
  v_submitted_participants INT;
BEGIN
  SELECT * INTO v_instance FROM evaluation_instances WHERE id = p_evaluation_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Evaluation instance not found'
      USING ERRCODE = 'P0004';
  END IF;

  -- Check if already completed
  IF v_instance.status = 'COMPLETED' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Evaluation is already completed'
      USING ERRCODE = 'P0007';
  END IF;

  IF v_instance.status = 'CANCELLED' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Cannot complete a cancelled evaluation'
      USING ERRCODE = 'P0007';
  END IF;

  SELECT * INTO v_template FROM evaluation_templates WHERE id = v_instance.template_id;

  -- Count participants
  SELECT COUNT(*), COUNT(*) FILTER (WHERE status = 'SUBMITTED')
  INTO v_total_participants, v_submitted_participants
  FROM evaluation_participants
  WHERE evaluation_id = p_evaluation_id;

  -- Validate completion based on participant type
  IF v_template.participant_type = 'PANEL' THEN
    -- Panel requires all participants to submit
    IF v_submitted_participants < v_total_participants AND NOT p_force THEN
      RAISE EXCEPTION 'EVALUATION_INCOMPLETE: % of % participants submitted. Use force-complete with note to override.',
        v_submitted_participants, v_total_participants
        USING ERRCODE = 'P0013';
    END IF;
  ELSIF v_template.participant_type = 'SINGLE' THEN
    -- Single requires the one participant to submit
    IF v_submitted_participants = 0 AND NOT p_force THEN
      RAISE EXCEPTION 'EVALUATION_INCOMPLETE: No response submitted yet.'
        USING ERRCODE = 'P0013';
    END IF;
  ELSIF v_template.participant_type = 'SEQUENTIAL' THEN
    -- Sequential requires at least one submission
    IF v_submitted_participants = 0 AND NOT p_force THEN
      RAISE EXCEPTION 'EVALUATION_INCOMPLETE: No responses submitted yet.'
        USING ERRCODE = 'P0013';
    END IF;
  END IF;

  -- Force-complete requires a note
  IF p_force AND (p_force_note IS NULL OR TRIM(p_force_note) = '') THEN
    RAISE EXCEPTION 'VALIDATION: Force-complete requires a note explaining the override.'
      USING ERRCODE = 'P0009';
  END IF;

  -- Mark as completed
  UPDATE evaluation_instances
  SET
    status = 'COMPLETED',
    completed_at = NOW(),
    updated_at = NOW(),
    force_completed = p_force,
    force_complete_note = p_force_note,
    force_completed_by = CASE WHEN p_force THEN p_user_id ELSE NULL END
  WHERE id = p_evaluation_id
  RETURNING * INTO v_instance;

  -- Aggregate signals from responses
  PERFORM aggregate_evaluation_signals(p_evaluation_id);

  RAISE LOG 'EVALUATION_COMPLETED: id=% app=% force=% participants=%/%',
    p_evaluation_id, v_instance.application_id, p_force, v_submitted_participants, v_total_participants;

  RETURN v_instance;
END;
$$;

COMMENT ON FUNCTION complete_evaluation IS 'Completes an evaluation and triggers signal aggregation. Force-complete requires note.';

-- ============================================================================
-- PART 10: RLS Policies
-- ============================================================================

-- evaluation_templates
ALTER TABLE evaluation_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant templates" ON evaluation_templates
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "Admins can manage templates" ON evaluation_templates
  FOR ALL USING (tenant_id = get_tenant_id() AND can_manage_settings());

-- evaluation_instances
ALTER TABLE evaluation_instances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant instances" ON evaluation_instances
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "HR can manage instances" ON evaluation_instances
  FOR ALL USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- evaluation_participants
ALTER TABLE evaluation_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant participants" ON evaluation_participants
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "Users can view their own participation" ON evaluation_participants
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "HR can manage participants" ON evaluation_participants
  FOR ALL USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- evaluation_responses
ALTER TABLE evaluation_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "HR can view all responses" ON evaluation_responses
  FOR SELECT USING (tenant_id = get_tenant_id() AND can_manage_tracking());

CREATE POLICY "Participants can view own responses" ON evaluation_responses
  FOR SELECT USING (
    participant_id IN (
      SELECT id FROM evaluation_participants WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Participants can insert own response" ON evaluation_responses
  FOR INSERT WITH CHECK (
    participant_id IN (
      SELECT id FROM evaluation_participants
      WHERE user_id = auth.uid() AND status = 'PENDING'
    )
  );
-- Note: No UPDATE policy - responses are immutable

-- application_signals
ALTER TABLE application_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "HR can view signals" ON application_signals
  FOR SELECT USING (tenant_id = get_tenant_id() AND can_manage_tracking());

CREATE POLICY "Admins can manage signals" ON application_signals
  FOR ALL USING (tenant_id = get_tenant_id() AND can_manage_settings());

-- action_execution_log
ALTER TABLE action_execution_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "HR can view execution log" ON action_execution_log
  FOR SELECT USING (tenant_id = get_tenant_id() AND can_manage_tracking());

CREATE POLICY "Admins can insert execution log" ON action_execution_log
  FOR INSERT WITH CHECK (tenant_id = get_tenant_id());

-- Note: No UPDATE/DELETE policy - execution log is immutable

-- ============================================================================
-- PART 11: Seed Functions + Triggers
-- ============================================================================

-- Seed default evaluation templates for a tenant
CREATE OR REPLACE FUNCTION seed_default_evaluation_templates(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO evaluation_templates (tenant_id, name, description, participant_type, signal_schema, default_aggregation)
  VALUES
    (p_tenant_id, 'Technical Interview', 'Technical skills assessment', 'SINGLE',
     '[
       {"key": "TECH_PASS", "type": "boolean", "label": "Technically qualified?", "aggregation": "MAJORITY"},
       {"key": "TECH_SCORE", "type": "integer", "label": "Technical Score (1-5)", "min": 1, "max": 5, "aggregation": "AVERAGE"},
       {"key": "TECH_NOTES", "type": "text", "label": "Technical Notes", "aggregation": null}
     ]'::jsonb, 'MAJORITY'),

    (p_tenant_id, 'Culture Council', 'Panel culture fit assessment', 'PANEL',
     '[
       {"key": "CULTURE_GO", "type": "boolean", "label": "Culture fit?", "aggregation": "MAJORITY"},
       {"key": "CULTURE_RISK", "type": "text", "label": "Risk Level", "aggregation": null}
     ]'::jsonb, 'MAJORITY'),

    (p_tenant_id, 'HR Screening', 'Initial HR screen', 'SINGLE',
     '[
       {"key": "HR_PASS", "type": "boolean", "label": "Proceed?", "aggregation": "MAJORITY"},
       {"key": "SALARY_FIT", "type": "boolean", "label": "Salary expectations fit?", "aggregation": "MAJORITY"},
       {"key": "HR_NOTES", "type": "text", "label": "Notes", "aggregation": null}
     ]'::jsonb, 'MAJORITY'),

    (p_tenant_id, 'Hiring Committee', 'Final hiring decision', 'PANEL',
     '[
       {"key": "HIRE_GO", "type": "boolean", "label": "Hire?", "aggregation": "UNANIMOUS"},
       {"key": "HIRE_LEVEL", "type": "text", "label": "Recommended Level", "aggregation": null}
     ]'::jsonb, 'UNANIMOUS')
  ON CONFLICT (tenant_id, name, version) DO NOTHING;
END;
$$;

-- Trigger: seed evaluation templates on tenant insert
CREATE OR REPLACE FUNCTION trg_seed_evaluation_templates_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM seed_default_evaluation_templates(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_evaluation_templates
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_evaluation_templates_fn();

-- ============================================================================
-- BACKFILL: Seed evaluation templates for all existing tenants
-- ============================================================================
DO $$
DECLARE
  v_tenant_id UUID;
BEGIN
  FOR v_tenant_id IN SELECT id FROM tenants LOOP
    PERFORM seed_default_evaluation_templates(v_tenant_id);
  END LOOP;
END;
$$;

-- ============================================================================
-- RPC: Submit evaluation response
-- ============================================================================

CREATE OR REPLACE FUNCTION submit_evaluation_response(
  p_evaluation_id UUID,
  p_user_id UUID,
  p_response_data JSONB
) RETURNS evaluation_responses
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_participant evaluation_participants%ROWTYPE;
  v_response evaluation_responses%ROWTYPE;
  v_instance evaluation_instances%ROWTYPE;
BEGIN
  -- Get participant record
  SELECT * INTO v_participant
  FROM evaluation_participants
  WHERE evaluation_id = p_evaluation_id AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN: User is not a participant in this evaluation'
      USING ERRCODE = 'P0008';
  END IF;

  IF v_participant.status = 'SUBMITTED' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Response already submitted'
      USING ERRCODE = 'P0007';
  END IF;

  IF v_participant.status = 'DECLINED' THEN
    RAISE EXCEPTION 'INVALID_ACTION: Participant has declined this evaluation'
      USING ERRCODE = 'P0007';
  END IF;

  -- Check evaluation is still open
  SELECT * INTO v_instance FROM evaluation_instances WHERE id = p_evaluation_id;
  IF v_instance.status NOT IN ('PENDING', 'IN_PROGRESS') THEN
    RAISE EXCEPTION 'INVALID_ACTION: Evaluation is no longer accepting responses (status: %)', v_instance.status
      USING ERRCODE = 'P0007';
  END IF;

  -- Insert response (immutable)
  INSERT INTO evaluation_responses (tenant_id, participant_id, response_data)
  VALUES (v_participant.tenant_id, v_participant.id, p_response_data)
  RETURNING * INTO v_response;

  -- Update participant status
  UPDATE evaluation_participants
  SET status = 'SUBMITTED', submitted_at = NOW()
  WHERE id = v_participant.id;

  -- Update evaluation instance status if needed
  IF v_instance.status = 'PENDING' THEN
    UPDATE evaluation_instances
    SET status = 'IN_PROGRESS', updated_at = NOW()
    WHERE id = p_evaluation_id;
  END IF;

  RAISE LOG 'EVALUATION_RESPONSE: evaluation=% participant=% user=%',
    p_evaluation_id, v_participant.id, p_user_id;

  RETURN v_response;
END;
$$;

COMMENT ON FUNCTION submit_evaluation_response IS 'Submit an evaluation response. Immutable once submitted.';

-- ============================================================================
-- RPC: Set manual signal (admin only)
-- ============================================================================

CREATE OR REPLACE FUNCTION set_manual_signal(
  p_application_id UUID,
  p_tenant_id UUID,
  p_user_id UUID,
  p_signal_key VARCHAR(100),
  p_signal_type VARCHAR(20),
  p_value TEXT,
  p_note TEXT DEFAULT NULL
) RETURNS application_signals
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_old_signal_id UUID;
  v_new_signal application_signals%ROWTYPE;
  v_value_boolean BOOLEAN;
  v_value_numeric NUMERIC;
  v_value_text TEXT;
BEGIN
  -- Validate signal type
  IF p_signal_type NOT IN ('boolean', 'integer', 'float', 'text') THEN
    RAISE EXCEPTION 'VALIDATION: Invalid signal type "%"', p_signal_type
      USING ERRCODE = 'P0009';
  END IF;

  -- Parse value based on type
  CASE p_signal_type
    WHEN 'boolean' THEN
      v_value_boolean := p_value::BOOLEAN;
    WHEN 'integer', 'float' THEN
      v_value_numeric := p_value::NUMERIC;
    WHEN 'text' THEN
      v_value_text := p_value;
  END CASE;

  -- Mark old signal as superseded
  SELECT id INTO v_old_signal_id
  FROM application_signals
  WHERE application_id = p_application_id
    AND signal_key = p_signal_key
    AND superseded_at IS NULL;

  IF v_old_signal_id IS NOT NULL THEN
    UPDATE application_signals
    SET superseded_at = NOW()
    WHERE id = v_old_signal_id;
  END IF;

  -- Insert new signal
  INSERT INTO application_signals (
    tenant_id, application_id, signal_key, signal_type,
    signal_value_boolean, signal_value_numeric, signal_value_text,
    source_type, set_by, set_at
  ) VALUES (
    p_tenant_id, p_application_id, p_signal_key, p_signal_type,
    v_value_boolean, v_value_numeric, v_value_text,
    'MANUAL', p_user_id, NOW()
  )
  RETURNING * INTO v_new_signal;

  -- Link old signal
  IF v_old_signal_id IS NOT NULL THEN
    UPDATE application_signals
    SET superseded_by = v_new_signal.id
    WHERE id = v_old_signal_id;
  END IF;

  RAISE LOG 'MANUAL_SIGNAL: app=% key=% value=% by=%',
    p_application_id, p_signal_key, p_value, p_user_id;

  RETURN v_new_signal;

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'VALIDATION: Failed to set signal - %', SQLERRM
    USING ERRCODE = 'P0009';
END;
$$;

COMMENT ON FUNCTION set_manual_signal IS 'Manually set a signal value. Admin only.';
