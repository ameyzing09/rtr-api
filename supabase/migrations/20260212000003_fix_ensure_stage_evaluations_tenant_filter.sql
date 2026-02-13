-- ============================================================================
-- Fix: ensure_stage_evaluations missing tenant filter + cleanup
-- ============================================================================
-- Bug: The query on stage_evaluations did not filter by se.tenant_id = p_tenant_id,
-- causing cross-tenant template references in evaluation_instances.
--
-- Part A: Fix the function — add tenant filter
-- Part B: Delete cross-tenant garbage rows
-- Part C: Re-run ensure for in-flight applications (idempotent)
-- Part D: Verify no duplicates remain
-- ============================================================================

-- ============================================================================
-- PART A: Fix ensure_stage_evaluations — add tenant filter to WHERE clause
-- ============================================================================

CREATE OR REPLACE FUNCTION ensure_stage_evaluations(
  p_tenant_id UUID,
  p_application_id UUID,
  p_stage_id UUID
) RETURNS INTEGER
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
      AND se.tenant_id = p_tenant_id          -- ← FIX: was missing
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

-- ============================================================================
-- PART B: Delete cross-tenant garbage
-- ============================================================================
-- Instances where ei.tenant_id != et.tenant_id are cross-tenant artifacts
-- created by the unfixed function.

DELETE FROM evaluation_instances ei
USING evaluation_templates et
WHERE ei.template_id = et.id
  AND ei.tenant_id != et.tenant_id;

-- ============================================================================
-- PART C: Re-run ensure for in-flight applications (idempotent)
-- ============================================================================
-- For every non-terminal application × its current stage's active stage_evaluations,
-- call the now-fixed ensure_stage_evaluations to create any missing instances.

DO $$
DECLARE
  v_app RECORD;
BEGIN
  FOR v_app IN
    SELECT aps.tenant_id, aps.application_id, aps.current_stage_id
    FROM application_pipeline_state aps
    WHERE aps.is_terminal = false
  LOOP
    PERFORM ensure_stage_evaluations(
      v_app.tenant_id,
      v_app.application_id,
      v_app.current_stage_id
    );
  END LOOP;
END;
$$;

-- ============================================================================
-- PART D: Verify no duplicates after cleanup
-- ============================================================================
-- This DO block raises an exception if any duplicate tuples remain, which
-- would abort the migration and surface the problem immediately.

DO $$
DECLARE
  v_dup_count INT;
BEGIN
  SELECT count(*) INTO v_dup_count
  FROM (
    SELECT tenant_id, application_id, stage_id, template_id
    FROM evaluation_instances
    GROUP BY tenant_id, application_id, stage_id, template_id
    HAVING count(*) > 1
  ) dupes;

  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'DATA_INTEGRITY: % duplicate evaluation_instance tuples found after cleanup', v_dup_count;
  END IF;
END;
$$;
