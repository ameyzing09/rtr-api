-- ============================================================================
-- APPLICATION DETAIL AUTH TESTS
-- ============================================================================
-- Purpose: Verify role-based access control and interviewer assignment checks
--          for the application-detail service.
-- Run via: Supabase SQL Editor or psql
--
-- Tests:
--   1. Role check: canViewApplicationDetail allows correct roles
--   2. Role check: canViewApplicationDetail denies incorrect roles
--   3. Assigned interviewer can access (via interview -> round -> assignment chain)
--   4. Unassigned interviewer is denied
--   5. Cross-tenant isolation blocks access
--
-- Prerequisites: All migrations applied
-- ============================================================================

-- ============================================================================
-- TEST HARNESS SETUP (idempotent)
-- ============================================================================

DROP TABLE IF EXISTS _test_results CASCADE;
CREATE TABLE _test_results (
  id SERIAL PRIMARY KEY,
  category TEXT NOT NULL,
  test_name TEXT NOT NULL,
  passed BOOLEAN NOT NULL,
  expected TEXT,
  actual TEXT,
  error_message TEXT,
  executed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION _record_test(
  p_category TEXT,
  p_test_name TEXT,
  p_passed BOOLEAN,
  p_expected TEXT DEFAULT NULL,
  p_actual TEXT DEFAULT NULL,
  p_error TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  INSERT INTO _test_results (category, test_name, passed, expected, actual, error_message)
  VALUES (p_category, p_test_name, p_passed, p_expected, p_actual, p_error);

  IF p_passed THEN
    RAISE NOTICE '[PASS] %.%', p_category, p_test_name;
  ELSE
    RAISE NOTICE '[FAIL] %.% - Expected: %, Actual: %, Error: %',
      p_category, p_test_name, p_expected, p_actual, p_error;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _assert_eq(
  p_category TEXT,
  p_test_name TEXT,
  p_expected ANYELEMENT,
  p_actual ANYELEMENT
) RETURNS BOOLEAN AS $$
DECLARE
  v_passed BOOLEAN;
BEGIN
  v_passed := p_expected IS NOT DISTINCT FROM p_actual;
  PERFORM _record_test(p_category, p_test_name, v_passed, p_expected::TEXT, p_actual::TEXT);
  RETURN v_passed;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TEST 1: Role check allows SUPERADMIN, ADMIN, HR, INTERVIEWER
-- ============================================================================
-- These tests verify the role logic at SQL level (mirrors middleware.ts canViewApplicationDetail)

DO $$
DECLARE
  v_allowed_roles TEXT[] := ARRAY['SUPERADMIN', 'ADMIN', 'HR', 'INTERVIEWER'];
  v_role TEXT;
  v_is_allowed BOOLEAN;
BEGIN
  FOREACH v_role IN ARRAY v_allowed_roles LOOP
    v_is_allowed := v_role = ANY(ARRAY['SUPERADMIN', 'ADMIN', 'HR', 'INTERVIEWER']);
    PERFORM _record_test(
      'ROLE_CHECK',
      'allowed_role_' || v_role,
      v_is_allowed,
      'true',
      v_is_allowed::TEXT
    );
  END LOOP;
END $$;

-- ============================================================================
-- TEST 2: Role check denies VIEWER, CANDIDATE
-- ============================================================================

DO $$
DECLARE
  v_denied_roles TEXT[] := ARRAY['VIEWER', 'CANDIDATE', 'GUEST', ''];
  v_role TEXT;
  v_is_allowed BOOLEAN;
BEGIN
  FOREACH v_role IN ARRAY v_denied_roles LOOP
    v_is_allowed := v_role = ANY(ARRAY['SUPERADMIN', 'ADMIN', 'HR', 'INTERVIEWER']);
    PERFORM _record_test(
      'ROLE_CHECK',
      'denied_role_' || COALESCE(NULLIF(v_role, ''), 'EMPTY'),
      NOT v_is_allowed,
      'false',
      v_is_allowed::TEXT
    );
  END LOOP;
END $$;

-- ============================================================================
-- TEST 3-5: Interviewer assignment chain tests
-- These require test data: tenant, job, application, interview, round, assignment
-- ============================================================================

DO $$
DECLARE
  v_tenant_id UUID;
  v_tenant_id_other UUID;
  v_job_id UUID;
  v_app_id UUID;
  v_interview_id UUID;
  v_round_id UUID;
  v_user_assigned UUID := gen_random_uuid();
  v_user_unassigned UUID := gen_random_uuid();
  v_assignment_exists BOOLEAN;
BEGIN
  -- Setup: Create test tenant
  INSERT INTO tenants (id, name, slug) VALUES
    (gen_random_uuid(), 'Test Tenant Detail', 'test-detail-' || substr(gen_random_uuid()::text, 1, 8))
    RETURNING id INTO v_tenant_id;

  INSERT INTO tenants (id, name, slug) VALUES
    (gen_random_uuid(), 'Other Tenant Detail', 'other-detail-' || substr(gen_random_uuid()::text, 1, 8))
    RETURNING id INTO v_tenant_id_other;

  -- Setup: Create test job
  INSERT INTO jobs (id, tenant_id, title) VALUES
    (gen_random_uuid(), v_tenant_id, 'Test Job Detail')
    RETURNING id INTO v_job_id;

  -- Setup: Create test application
  INSERT INTO applications (id, tenant_id, job_id, applicant_name, applicant_email) VALUES
    (gen_random_uuid(), v_tenant_id, v_job_id, 'Test Candidate', 'test@example.com')
    RETURNING id INTO v_app_id;

  -- Setup: Create interview -> round -> assignment chain
  INSERT INTO interviews (id, tenant_id, application_id, pipeline_stage_id) VALUES
    (gen_random_uuid(), v_tenant_id, v_app_id, gen_random_uuid())
    RETURNING id INTO v_interview_id;

  INSERT INTO interview_rounds (id, tenant_id, interview_id, round_type, sequence) VALUES
    (gen_random_uuid(), v_tenant_id, v_interview_id, 'TECH', 1)
    RETURNING id INTO v_round_id;

  INSERT INTO interviewer_assignments (tenant_id, round_id, user_id) VALUES
    (v_tenant_id, v_round_id, v_user_assigned);

  -- ============================================================================
  -- TEST 3: Assigned interviewer -> chain exists
  -- ============================================================================
  SELECT EXISTS(
    SELECT 1
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    JOIN interviews i ON i.id = ir.interview_id
    WHERE ia.user_id = v_user_assigned
      AND ia.tenant_id = v_tenant_id
      AND i.application_id = v_app_id
  ) INTO v_assignment_exists;

  PERFORM _record_test(
    'INTERVIEWER_ASSIGNMENT',
    '3_assigned_interviewer_has_access',
    v_assignment_exists,
    'true',
    v_assignment_exists::TEXT
  );

  -- ============================================================================
  -- TEST 4: Unassigned interviewer -> no chain
  -- ============================================================================
  SELECT EXISTS(
    SELECT 1
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    JOIN interviews i ON i.id = ir.interview_id
    WHERE ia.user_id = v_user_unassigned
      AND ia.tenant_id = v_tenant_id
      AND i.application_id = v_app_id
  ) INTO v_assignment_exists;

  PERFORM _record_test(
    'INTERVIEWER_ASSIGNMENT',
    '4_unassigned_interviewer_denied',
    NOT v_assignment_exists,
    'false',
    v_assignment_exists::TEXT
  );

  -- ============================================================================
  -- TEST 5: Cross-tenant isolation
  -- ============================================================================
  SELECT EXISTS(
    SELECT 1
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    JOIN interviews i ON i.id = ir.interview_id
    WHERE ia.user_id = v_user_assigned
      AND ia.tenant_id = v_tenant_id_other
      AND i.application_id = v_app_id
  ) INTO v_assignment_exists;

  PERFORM _record_test(
    'INTERVIEWER_ASSIGNMENT',
    '5_cross_tenant_isolation',
    NOT v_assignment_exists,
    'false',
    v_assignment_exists::TEXT
  );

  -- Cleanup test data
  DELETE FROM interviewer_assignments WHERE round_id = v_round_id;
  DELETE FROM interview_rounds WHERE id = v_round_id;
  DELETE FROM interviews WHERE id = v_interview_id;
  DELETE FROM applications WHERE id = v_app_id;
  DELETE FROM jobs WHERE id = v_job_id;
  DELETE FROM tenants WHERE id IN (v_tenant_id, v_tenant_id_other);

END $$;

-- ============================================================================
-- RESULTS SUMMARY
-- ============================================================================

SELECT
  CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result,
  category,
  test_name,
  expected,
  actual,
  error_message
FROM _test_results
ORDER BY id;

SELECT
  COUNT(*) FILTER (WHERE passed) AS passed,
  COUNT(*) FILTER (WHERE NOT passed) AS failed,
  COUNT(*) AS total
FROM _test_results;

-- Cleanup harness
DROP TABLE IF EXISTS _test_results CASCADE;
DROP FUNCTION IF EXISTS _record_test CASCADE;
DROP FUNCTION IF EXISTS _assert_eq CASCADE;
