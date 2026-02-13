-- ============================================================================
-- Auto-Add Evaluation Participants for HR-Conducted Stages
-- ============================================================================
-- Problem: ensure_stage_evaluations() auto-creates evaluation_instances but
-- never assigns participants. For HR-conducted stages (Phone Screen, Applied,
-- Offer, Hired), this leaves evaluations in limbo — submit_evaluation_response
-- enforces participant-only submission, so nobody can respond.
--
-- Part 1: Helper function resolve_hr_participant()
-- Part 2: Updated ensure_stage_evaluations() with auto-participant logic
-- Part 3: Backfill in-flight HR evaluations missing participants
-- ============================================================================

-- ============================================================================
-- PART 1: Helper function — resolve_hr_participant(p_tenant_id, p_application_id)
-- ============================================================================
-- Returns the user_id of the appropriate HR participant for an application.
-- Priority: job creator (if active in tenant) → tenant owner → NULL
-- STABLE: reads only, no side effects. No SECURITY DEFINER — called from
-- functions that already run with elevated privileges.

CREATE OR REPLACE FUNCTION resolve_hr_participant(
  p_tenant_id UUID,
  p_application_id UUID
) RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_job_creator UUID;
  v_resolved_user UUID;
BEGIN
  -- Priority 1: Job creator, if active in the same tenant
  SELECT j.created_by INTO v_job_creator
  FROM applications a
  JOIN jobs j ON j.id = a.job_id
  WHERE a.id = p_application_id;

  IF v_job_creator IS NOT NULL THEN
    SELECT up.id INTO v_resolved_user
    FROM user_profiles up
    WHERE up.id = v_job_creator
      AND up.tenant_id = p_tenant_id
      AND up.is_active = true;

    IF v_resolved_user IS NOT NULL THEN
      RETURN v_resolved_user;
    END IF;
  END IF;

  -- Priority 2: Tenant owner (active)
  SELECT up.id INTO v_resolved_user
  FROM user_profiles up
  WHERE up.tenant_id = p_tenant_id
    AND up.is_owner = true
    AND up.is_active = true
  LIMIT 1;

  -- Returns NULL if no tenant owner found either (silent skip)
  RETURN v_resolved_user;
END;
$$;

COMMENT ON FUNCTION resolve_hr_participant IS 'Resolves the HR participant for an application: job creator → tenant owner → NULL';

-- ============================================================================
-- PART 2: Updated ensure_stage_evaluations() with HR auto-participant
-- ============================================================================
-- Additions to existing logic:
-- 1. Before the loop: check if stage is HR-conducted (UPPER(conducted_by) = 'HR')
-- 2. Before the loop: if HR, resolve participant (once — same user for all evals)
-- 3. Inside the loop: after instance INSERT, add participant if HR + user resolved
-- Also adds SET search_path to pin search path on SECURITY DEFINER function.

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
    ON CONFLICT (tenant_id, application_id, template_id, stage_id) DO NOTHING;

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
        AND ei.stage_id = p_stage_id;

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
-- PART 3: Backfill in-flight HR evaluations missing participants
-- ============================================================================
-- Targets evaluation_instances where:
--   - Stage is HR-conducted
--   - Status is PENDING or IN_PROGRESS
--   - Zero participants exist
-- Resolves participant via resolve_hr_participant() and inserts.

DO $$
DECLARE
  v_rec RECORD;
  v_participant_id UUID;
BEGIN
  FOR v_rec IN
    SELECT ei.id AS instance_id,
           ei.tenant_id,
           ei.application_id
    FROM evaluation_instances ei
    JOIN pipeline_stages ps ON ps.id = ei.stage_id
    WHERE UPPER(ps.conducted_by) = 'HR'
      AND ei.status IN ('PENDING', 'IN_PROGRESS')
      AND NOT EXISTS (
        SELECT 1 FROM evaluation_participants ep
        WHERE ep.evaluation_id = ei.id
      )
  LOOP
    v_participant_id := resolve_hr_participant(v_rec.tenant_id, v_rec.application_id);

    IF v_participant_id IS NOT NULL THEN
      INSERT INTO evaluation_participants (
        tenant_id, evaluation_id, user_id, status
      ) VALUES (
        v_rec.tenant_id, v_rec.instance_id, v_participant_id, 'PENDING'
      )
      ON CONFLICT (evaluation_id, user_id) DO NOTHING;
    END IF;
  END LOOP;
END;
$$;
