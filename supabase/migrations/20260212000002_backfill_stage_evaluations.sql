-- ============================================================================
-- Migration: Backfill stage_evaluations for default pipeline
-- ============================================================================
-- Populates stage_evaluations for all tenants × default pipeline stages,
-- sets required = true for interview stages, and adds a tenant-creation
-- trigger so future tenants get seeded automatically.
-- ============================================================================

-- ============================================================================
-- PART 1: Fix seed function — required = true for interview stages
-- ============================================================================

CREATE OR REPLACE FUNCTION seed_default_stage_evaluations(
  p_stage_id UUID,
  p_tenant_id UUID,
  p_stage_type VARCHAR
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_template_name TEXT;
  v_template_id UUID;
BEGIN
  -- Map stage_type to default evaluation template name
  v_template_name := CASE p_stage_type
    WHEN 'screening'    THEN 'HR Screening'
    WHEN 'interview'    THEN 'Technical Interview'
    WHEN 'review'       THEN 'Culture Council'
    WHEN 'final_review' THEN 'Hiring Committee'
    ELSE NULL
  END;

  -- No default template for this stage type
  IF v_template_name IS NULL THEN
    RETURN;
  END IF;

  -- Find the template (tenant-scoped, active, latest version)
  SELECT id INTO v_template_id
  FROM evaluation_templates
  WHERE tenant_id = p_tenant_id
    AND name = v_template_name
    AND is_active = true
    AND is_latest = true
  LIMIT 1;

  -- Template doesn't exist yet — skip silently
  IF v_template_id IS NULL THEN
    RAISE LOG 'SEED_STAGE_EVAL: No template "%" found for tenant=%, skipping', v_template_name, p_tenant_id;
    RETURN;
  END IF;

  -- Insert stage evaluation config
  INSERT INTO stage_evaluations (
    tenant_id, stage_id, evaluation_template_id, execution_order, auto_create, required
  ) VALUES (
    p_tenant_id, p_stage_id, v_template_id, 1, true, (p_stage_type = 'interview')
  )
  ON CONFLICT (tenant_id, stage_id, execution_order, evaluation_template_id) DO NOTHING;

  RAISE LOG 'SEED_STAGE_EVAL: stage=% type=% template=% tenant=%', p_stage_id, p_stage_type, v_template_id, p_tenant_id;
END;
$$;

-- ============================================================================
-- PART 2: Trigger — seed stage evals when a new tenant is created
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_seed_tenant_stage_evaluations_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stage RECORD;
BEGIN
  FOR v_stage IN
    SELECT id, stage_type FROM pipeline_stages
    WHERE tenant_id IS NULL
      AND stage_type IN ('screening', 'interview', 'review', 'final_review')
  LOOP
    PERFORM seed_default_stage_evaluations(v_stage.id, NEW.id, v_stage.stage_type);
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_tenant_stage_evaluations
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_tenant_stage_evaluations_fn();

-- ============================================================================
-- PART 3: Backfill existing tenants × default pipeline stages
-- ============================================================================

DO $$
DECLARE
  v_stage RECORD;
  v_tenant_id UUID;
BEGIN
  FOR v_stage IN
    SELECT id, stage_type FROM pipeline_stages
    WHERE tenant_id IS NULL
      AND stage_type IN ('screening', 'interview', 'review', 'final_review')
  LOOP
    FOR v_tenant_id IN SELECT id FROM tenants LOOP
      PERFORM seed_default_stage_evaluations(v_stage.id, v_tenant_id, v_stage.stage_type);
    END LOOP;
  END LOOP;
END;
$$;
