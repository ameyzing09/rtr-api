-- ============================================================================
-- Interview Domain - Phase 1 Foundation
-- ============================================================================
-- Owns: interview intent, rounds, assignments & feedback
-- Emits: signals into application_signals (source_type = 'INTERVIEW')
-- Never touches: tracking state, evaluation data
-- ============================================================================

-- ============================================================================
-- 1.1 Extend application_signals source_type to include INTERVIEW
-- ============================================================================

ALTER TABLE application_signals
  DROP CONSTRAINT IF EXISTS application_signals_source_type_check;

ALTER TABLE application_signals
  ADD CONSTRAINT application_signals_source_type_check
  CHECK (source_type IN ('EVALUATION', 'MANUAL', 'SYSTEM', 'INTERVIEW'));

-- ============================================================================
-- 1.2 interviews table
-- ============================================================================

CREATE TABLE IF NOT EXISTS interviews (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id),
  application_id  UUID NOT NULL,           -- no FK to applications (cross-service boundary)
  pipeline_stage_id UUID NOT NULL,         -- snapshot at creation time, no FK into tracking
  status          TEXT NOT NULL DEFAULT 'PLANNED'
                  CHECK (status IN ('PLANNED', 'IN_PROGRESS', 'CANCELLED')),
                  -- COMPLETED deferred to Phase 2 (no semantic meaning without interview-level aggregation)
  created_by      UUID,                    -- the user who initiated the interview
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 1.3 interview_rounds table
-- ============================================================================

CREATE TABLE IF NOT EXISTS interview_rounds (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES tenants(id),
  interview_id  UUID NOT NULL REFERENCES interviews(id) ON DELETE CASCADE,
  round_type    TEXT NOT NULL,    -- HR, TECH, MANAGER, etc.
  sequence      INT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(interview_id, sequence)
);

-- ============================================================================
-- 1.4 interviewer_assignments table
-- ============================================================================
-- Tracks who is expected to participate in each round.
-- Feedback submission validates submitted_by exists in assignments for that round.
-- Enables "my pending interviews" query (assigned but no feedback yet).

CREATE TABLE IF NOT EXISTS interviewer_assignments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id),
  round_id    UUID NOT NULL REFERENCES interview_rounds(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(round_id, user_id)   -- one assignment per user per round
);

-- ============================================================================
-- 1.5 interview_feedback table
-- ============================================================================

CREATE TABLE IF NOT EXISTS interview_feedback (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES tenants(id),
  round_id      UUID NOT NULL REFERENCES interview_rounds(id),
  submitted_by  UUID NOT NULL,
  decision      TEXT NOT NULL CHECK (decision IN ('PASS', 'FAIL', 'NEUTRAL')),
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(round_id, submitted_by)   -- one feedback per interviewer per round
);

-- ============================================================================
-- 1.6 RLS Policies
-- ============================================================================

-- interviews
ALTER TABLE interviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant interviews" ON interviews
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "HR can manage interviews" ON interviews
  FOR INSERT WITH CHECK (tenant_id = get_tenant_id() AND can_manage_tracking());

CREATE POLICY "HR can update interviews" ON interviews
  FOR UPDATE USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- interview_rounds
ALTER TABLE interview_rounds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant rounds" ON interview_rounds
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "HR can manage rounds" ON interview_rounds
  FOR INSERT WITH CHECK (tenant_id = get_tenant_id() AND can_manage_tracking());

CREATE POLICY "HR can update rounds" ON interview_rounds
  FOR UPDATE USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- interviewer_assignments
ALTER TABLE interviewer_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant assignments" ON interviewer_assignments
  FOR SELECT USING (tenant_id = get_tenant_id());

CREATE POLICY "HR can manage assignments" ON interviewer_assignments
  FOR INSERT WITH CHECK (tenant_id = get_tenant_id() AND can_manage_tracking());

CREATE POLICY "HR can update assignments" ON interviewer_assignments
  FOR UPDATE USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- interview_feedback
ALTER TABLE interview_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own tenant feedback" ON interview_feedback
  FOR SELECT USING (tenant_id = get_tenant_id());

-- INTERVIEWER INSERT is intentionally broad at DB level.
-- The handler enforces assignment validation (user must be in interviewer_assignments for the round).
-- This avoids complex RLS subqueries while keeping the invariant in application code.
-- Handler also enforces: no feedback on CANCELLED interviews (cancellation state lives on parent interviews row).
CREATE POLICY "Interviewers can submit feedback" ON interview_feedback
  FOR INSERT WITH CHECK (tenant_id = get_tenant_id() AND can_manage_feedback());

CREATE POLICY "HR can manage feedback" ON interview_feedback
  FOR UPDATE USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- No DELETE policies on any table (soft-delete via status = CANCELLED)

-- ============================================================================
-- 1.7 Indexes
-- ============================================================================

CREATE INDEX idx_interviews_tenant ON interviews(tenant_id);
CREATE INDEX idx_interviews_application ON interviews(application_id);
CREATE INDEX idx_interviews_tenant_app ON interviews(tenant_id, application_id);
CREATE INDEX idx_interview_rounds_interview ON interview_rounds(interview_id);
CREATE INDEX idx_interviewer_assignments_round ON interviewer_assignments(round_id);
CREATE INDEX idx_interviewer_assignments_user ON interviewer_assignments(user_id);
CREATE INDEX idx_interviewer_assignments_user_round ON interviewer_assignments(user_id, round_id);
CREATE INDEX idx_interview_feedback_round ON interview_feedback(round_id);

-- ============================================================================
-- 1.8 Triggers
-- ============================================================================

-- Reuse existing update_updated_at() trigger function from 20260112000003_triggers.sql
CREATE TRIGGER update_interviews_updated_at
  BEFORE UPDATE ON interviews
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================================
-- 1.9 emit_interview_signal RPC
-- ============================================================================
-- Follows the exact pattern from set_manual_signal.
-- Supersession is scoped to source_type = 'INTERVIEW' only — never nukes
-- manual overrides or evaluation signals.
-- Phase 1: per-feedback, last-write-wins. No interview-level aggregation.

CREATE OR REPLACE FUNCTION emit_interview_signal(
  p_application_id UUID,
  p_tenant_id UUID,
  p_pipeline_stage_id UUID,
  p_decision TEXT,       -- PASS | FAIL | NEUTRAL
  p_source_id UUID,      -- interview_feedback.id
  p_user_id UUID
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_signal_key TEXT;
  v_old_signal_id UUID;
  v_new_signal_id UUID;
BEGIN
  -- NEUTRAL → no signal emitted (just stored as feedback)
  IF p_decision = 'NEUTRAL' THEN
    RETURN;
  END IF;

  -- Determine signal key
  IF p_decision = 'PASS' THEN
    v_signal_key := 'INTERVIEW_PASS';
  ELSIF p_decision = 'FAIL' THEN
    v_signal_key := 'INTERVIEW_FAIL';
  ELSE
    RAISE EXCEPTION 'VALIDATION: Invalid decision "%"', p_decision
      USING ERRCODE = 'P0009';
  END IF;

  -- Supersede ALL existing interview signals for this application
  -- CRITICAL: scoped to source_type = 'INTERVIEW' only — NEVER supersede signals from other sources
  FOR v_old_signal_id IN
    SELECT id FROM application_signals
    WHERE application_id = p_application_id
      AND signal_key IN ('INTERVIEW_PASS', 'INTERVIEW_FAIL')
      AND source_type = 'INTERVIEW'
      AND superseded_at IS NULL
  LOOP
    UPDATE application_signals
    SET superseded_at = NOW()
    WHERE id = v_old_signal_id;
  END LOOP;

  -- Insert new signal
  INSERT INTO application_signals (
    tenant_id, application_id, signal_key, signal_type,
    signal_value_boolean, signal_value_numeric, signal_value_text,
    source_type, source_id, set_by, set_at
  ) VALUES (
    p_tenant_id, p_application_id, v_signal_key, 'boolean',
    true, NULL, NULL,
    'INTERVIEW', p_source_id, p_user_id, NOW()
  )
  RETURNING id INTO v_new_signal_id;

  -- Link old signals to new (audit trail)
  UPDATE application_signals
  SET superseded_by = v_new_signal_id
  WHERE application_id = p_application_id
    AND signal_key IN ('INTERVIEW_PASS', 'INTERVIEW_FAIL')
    AND source_type = 'INTERVIEW'
    AND superseded_at IS NOT NULL
    AND superseded_by IS NULL
    AND id != v_new_signal_id;

EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'VALIDATION: Failed to emit interview signal - %', SQLERRM
    USING ERRCODE = 'P0009';
END;
$$;
