-- ============================================================================
-- Interview ↔ Evaluation Bridge
-- ============================================================================
-- 1. Add evaluation_instance_id to interview_rounds
-- 2. Drop interview_feedback (0 rows, no data loss)
-- 3. Drop emit_interview_signal RPC
-- 4. INTERVIEWER evaluation capabilities (feedback:*)
-- 5. Tighten evaluation RLS — scoped visibility
-- ============================================================================

-- 1. Add evaluation_instance_id to interview_rounds
ALTER TABLE interview_rounds
  ADD COLUMN evaluation_instance_id UUID NULL;

CREATE INDEX idx_interview_rounds_eval_instance
  ON interview_rounds(evaluation_instance_id);

-- 2. Drop interview_feedback (0 rows, no data loss)
DROP TABLE IF EXISTS interview_feedback CASCADE;

-- 3. Drop emit_interview_signal RPC (hard delete, not deprecate)
DROP FUNCTION IF EXISTS emit_interview_signal(UUID, UUID, UUID, TEXT, UUID, UUID);

-- NOTE: Keep INTERVIEW in application_signals source_type check — harmless, avoids future migration.
-- NOTE: No FK on evaluation_instance_id (cross-service boundary pattern).

-- ============================================================================
-- 4. INTERVIEWER evaluation capabilities (A1)
-- ============================================================================
-- Use feedback:* names to match frontend PERMISSIONS.FEEDBACK_* constants.
-- Additive only — do NOT rewrite seed_default_capabilities().

-- 4a. Backfill for all existing tenants
INSERT INTO role_capabilities (tenant_id, role_name, capability)
SELECT t.id, r.role_name, r.capability
FROM tenants t
CROSS JOIN (VALUES
  ('SUPERADMIN',  'feedback:list'),
  ('SUPERADMIN',  'feedback:read'),
  ('SUPERADMIN',  'feedback:create'),
  ('ADMIN',       'feedback:list'),
  ('ADMIN',       'feedback:read'),
  ('ADMIN',       'feedback:create'),
  ('HR',          'feedback:list'),
  ('HR',          'feedback:read'),
  ('HR',          'feedback:create'),
  ('INTERVIEWER', 'feedback:list'),
  ('INTERVIEWER', 'feedback:read'),
  ('INTERVIEWER', 'feedback:create')
) AS r(role_name, capability)
ON CONFLICT (tenant_id, role_name, capability) DO NOTHING;

-- 4b. Additive seed function for new tenants (called from tenant creation trigger)
-- Does NOT replace seed_default_capabilities — appends only.
CREATE OR REPLACE FUNCTION seed_eval_capabilities(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO role_capabilities (tenant_id, role_name, capability)
  VALUES
    (p_tenant_id, 'SUPERADMIN',  'feedback:list'),
    (p_tenant_id, 'SUPERADMIN',  'feedback:read'),
    (p_tenant_id, 'SUPERADMIN',  'feedback:create'),
    (p_tenant_id, 'ADMIN',       'feedback:list'),
    (p_tenant_id, 'ADMIN',       'feedback:read'),
    (p_tenant_id, 'ADMIN',       'feedback:create'),
    (p_tenant_id, 'HR',          'feedback:list'),
    (p_tenant_id, 'HR',          'feedback:read'),
    (p_tenant_id, 'HR',          'feedback:create'),
    (p_tenant_id, 'INTERVIEWER', 'feedback:list'),
    (p_tenant_id, 'INTERVIEWER', 'feedback:read'),
    (p_tenant_id, 'INTERVIEWER', 'feedback:create')
  ON CONFLICT (tenant_id, role_name, capability) DO NOTHING;
END;
$$;

-- 4c. Separate trigger for eval capabilities — does NOT touch trg_seed_capabilities_fn()
CREATE OR REPLACE FUNCTION trg_seed_eval_capabilities_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM seed_eval_capabilities(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_eval_capabilities
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION trg_seed_eval_capabilities_fn();

-- ============================================================================
-- 5. Tighten evaluation RLS — scoped visibility (A2)
-- ============================================================================

-- 5a. evaluation_instances: replace broad SELECT with tenant+participant-scoped
DROP POLICY IF EXISTS "Users can view own tenant instances" ON evaluation_instances;

CREATE POLICY "Participants can view assigned instances" ON evaluation_instances
  FOR SELECT USING (
    tenant_id = get_tenant_id()
    AND EXISTS (
      SELECT 1 FROM evaluation_participants ep
      WHERE ep.evaluation_id = evaluation_instances.id
        AND ep.user_id = auth.uid()
        AND ep.tenant_id = evaluation_instances.tenant_id
    )
  );

-- 5b. Ensure HR+ policies exist with proper WITH CHECK — deterministic DROP+CREATE
DROP POLICY IF EXISTS "HR can manage instances" ON evaluation_instances;
CREATE POLICY "HR can manage instances" ON evaluation_instances
  FOR ALL
  USING (tenant_id = get_tenant_id() AND can_manage_tracking())
  WITH CHECK (tenant_id = get_tenant_id() AND can_manage_tracking());

DROP POLICY IF EXISTS "HR can manage participants" ON evaluation_participants;
CREATE POLICY "HR can manage participants" ON evaluation_participants
  FOR ALL
  USING (tenant_id = get_tenant_id() AND can_manage_tracking())
  WITH CHECK (tenant_id = get_tenant_id() AND can_manage_tracking());

DROP POLICY IF EXISTS "HR can view all responses" ON evaluation_responses;
CREATE POLICY "HR can view all responses" ON evaluation_responses
  FOR SELECT
  USING (tenant_id = get_tenant_id() AND can_manage_tracking());

-- 5c. evaluation_participants: drop broad tenant SELECT, keep user-scoped
DROP POLICY IF EXISTS "Users can view own tenant participants" ON evaluation_participants;
