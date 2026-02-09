-- ============================================================================
-- CROSS-SERVICE CONTRACT TESTS
-- ============================================================================
-- Purpose: Verify RPC signatures and return types that form cross-service
--          boundaries. If any of these fail, a consumer service will break.
-- Run via: Supabase SQL Editor or psql
--
-- Tests use pg_proc / pg_type introspection only — no test data needed.
--
-- Contracts tested:
--   1. attach_application_to_pipeline_v1 (jobs → tracking)
--   2. get_application_by_token_v1       (public → tracking status)
--   3. get_action_signal_status           (tracking → evaluations)
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
-- CONTRACT 1: attach_application_to_pipeline_v1 (jobs → tracking)
-- ============================================================================

DO $$
DECLARE
  v_exists BOOLEAN;
  v_return_type TEXT;
  v_attr_count INT;
  v_has_application_id BOOLEAN;
  v_has_current_stage_id BOOLEAN;
  v_has_status BOOLEAN;
  v_has_is_terminal BOOLEAN;
BEGIN
  -- 1.1: Function exists
  SELECT EXISTS(
    SELECT 1 FROM pg_proc WHERE proname = 'attach_application_to_pipeline_v1'
  ) INTO v_exists;
  PERFORM _record_test('CONTRACT_1_ATTACH', '1.1_function_exists', v_exists,
    'true', v_exists::TEXT);

  -- 1.2: Returns tracking_state_result
  SELECT prorettype::regtype::text INTO v_return_type
  FROM pg_proc WHERE proname = 'attach_application_to_pipeline_v1';
  PERFORM _assert_eq('CONTRACT_1_ATTACH', '1.2_returns_tracking_state_result',
    'tracking_state_result', v_return_type);

  -- 1.3: tracking_state_result has exactly 10 attributes
  SELECT COUNT(*) INTO v_attr_count
  FROM pg_attribute
  WHERE attrelid = 'tracking_state_result'::regclass
    AND attnum > 0;
  PERFORM _assert_eq('CONTRACT_1_ATTACH', '1.3_type_has_10_attributes',
    10, v_attr_count);

  -- 1.4: Critical columns exist
  SELECT EXISTS(
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'tracking_state_result'::regclass AND attname = 'application_id'
  ) INTO v_has_application_id;
  PERFORM _record_test('CONTRACT_1_ATTACH', '1.4a_has_application_id', v_has_application_id,
    'true', v_has_application_id::TEXT);

  SELECT EXISTS(
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'tracking_state_result'::regclass AND attname = 'current_stage_id'
  ) INTO v_has_current_stage_id;
  PERFORM _record_test('CONTRACT_1_ATTACH', '1.4b_has_current_stage_id', v_has_current_stage_id,
    'true', v_has_current_stage_id::TEXT);

  SELECT EXISTS(
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'tracking_state_result'::regclass AND attname = 'status'
  ) INTO v_has_status;
  PERFORM _record_test('CONTRACT_1_ATTACH', '1.4c_has_status', v_has_status,
    'true', v_has_status::TEXT);

  SELECT EXISTS(
    SELECT 1 FROM pg_attribute
    WHERE attrelid = 'tracking_state_result'::regclass AND attname = 'is_terminal'
  ) INTO v_has_is_terminal;
  PERFORM _record_test('CONTRACT_1_ATTACH', '1.4d_has_is_terminal', v_has_is_terminal,
    'true', v_has_is_terminal::TEXT);
END;
$$;

-- ============================================================================
-- CONTRACT 2: get_application_by_token_v1 (public → tracking status)
-- ============================================================================

DO $$
DECLARE
  v_exists BOOLEAN;
  v_col_names TEXT[];
  v_has_job_title BOOLEAN;
  v_has_current_stage BOOLEAN;
  v_has_status_display_name BOOLEAN;
  v_has_applied_at BOOLEAN;
  v_has_last_updated_at BOOLEAN;
  v_col_count INT;
BEGIN
  -- 2.1: Function exists
  SELECT EXISTS(
    SELECT 1 FROM pg_proc WHERE proname = 'get_application_by_token_v1'
  ) INTO v_exists;
  PERFORM _record_test('CONTRACT_2_TOKEN', '2.1_function_exists', v_exists,
    'true', v_exists::TEXT);

  -- 2.2: Return signature contains all 5 locked columns
  -- For RETURNS TABLE functions, output columns are stored in proargnames/proargmodes
  SELECT ARRAY(
    SELECT unnest(proargnames)[i]
    FROM pg_proc,
         generate_series(1, array_length(proargnames, 1)) AS i
    WHERE proname = 'get_application_by_token_v1'
      AND (proargmodes IS NULL OR unnest(proargmodes)[i] = 't')
  ) INTO v_col_names;

  -- Fallback: query proallargtypes + proargnames for TABLE return columns
  SELECT ARRAY(
    SELECT proargnames[i]
    FROM pg_proc,
         generate_series(1, cardinality(proargnames)) AS i
    WHERE proname = 'get_application_by_token_v1'
      AND proargmodes[i] = 't'
  ) INTO v_col_names;

  v_has_job_title := 'job_title' = ANY(v_col_names);
  PERFORM _record_test('CONTRACT_2_TOKEN', '2.2a_has_job_title', v_has_job_title,
    'true', v_has_job_title::TEXT);

  v_has_current_stage := 'current_stage' = ANY(v_col_names);
  PERFORM _record_test('CONTRACT_2_TOKEN', '2.2b_has_current_stage', v_has_current_stage,
    'true', v_has_current_stage::TEXT);

  v_has_status_display_name := 'status_display_name' = ANY(v_col_names);
  PERFORM _record_test('CONTRACT_2_TOKEN', '2.2c_has_status_display_name', v_has_status_display_name,
    'true', v_has_status_display_name::TEXT);

  v_has_applied_at := 'applied_at' = ANY(v_col_names);
  PERFORM _record_test('CONTRACT_2_TOKEN', '2.2d_has_applied_at', v_has_applied_at,
    'true', v_has_applied_at::TEXT);

  v_has_last_updated_at := 'last_updated_at' = ANY(v_col_names);
  PERFORM _record_test('CONTRACT_2_TOKEN', '2.2e_has_last_updated_at', v_has_last_updated_at,
    'true', v_has_last_updated_at::TEXT);

  -- 2.3: Exactly 5 output columns (no accidental additions)
  SELECT cardinality(v_col_names) INTO v_col_count;
  PERFORM _assert_eq('CONTRACT_2_TOKEN', '2.3_exactly_5_output_columns',
    5, v_col_count);
END;
$$;

-- ============================================================================
-- CONTRACT 3: get_action_signal_status (tracking → evaluations)
-- ============================================================================

DO $$
DECLARE
  v_exists BOOLEAN;
  v_return_type TEXT;
  v_result JSONB;
  v_has_signals_met BOOLEAN;
  v_has_conditions BOOLEAN;
  v_signals_met BOOLEAN;
BEGIN
  -- 3.1: Function exists and returns jsonb
  SELECT EXISTS(
    SELECT 1 FROM pg_proc WHERE proname = 'get_action_signal_status'
  ) INTO v_exists;
  PERFORM _record_test('CONTRACT_3_SIGNALS', '3.1a_function_exists', v_exists,
    'true', v_exists::TEXT);

  SELECT prorettype::regtype::text INTO v_return_type
  FROM pg_proc WHERE proname = 'get_action_signal_status';
  PERFORM _assert_eq('CONTRACT_3_SIGNALS', '3.1b_returns_jsonb',
    'jsonb', v_return_type);

  -- 3.2: Call with fake UUIDs → verify default shape
  SELECT get_action_signal_status(
    '00000000-0000-0000-0000-000000000000'::uuid,
    'FAKE_ACTION',
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid
  ) INTO v_result;

  v_has_signals_met := v_result ? 'signalsMet';
  PERFORM _record_test('CONTRACT_3_SIGNALS', '3.2a_has_signalsMet_key', v_has_signals_met,
    'true', v_has_signals_met::TEXT);

  v_has_conditions := v_result ? 'conditions';
  PERFORM _record_test('CONTRACT_3_SIGNALS', '3.2b_has_conditions_key', v_has_conditions,
    'true', v_has_conditions::TEXT);

  -- 3.3: signalsMet defaults to true (no conditions = all met)
  v_signals_met := (v_result->>'signalsMet')::boolean;
  PERFORM _assert_eq('CONTRACT_3_SIGNALS', '3.3_signalsMet_defaults_true',
    TRUE, v_signals_met);
END;
$$;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================

DO $$
DECLARE
  v_total INT;
  v_passed INT;
  v_failed INT;
  v_category_summary RECORD;
BEGIN
  SELECT COUNT(*), COUNT(*) FILTER (WHERE passed), COUNT(*) FILTER (WHERE NOT passed)
  INTO v_total, v_passed, v_failed
  FROM _test_results;

  RAISE NOTICE '';
  RAISE NOTICE '============================================';
  RAISE NOTICE 'CROSS-SERVICE CONTRACT TEST SUMMARY';
  RAISE NOTICE '============================================';
  RAISE NOTICE 'Total:  %', v_total;
  RAISE NOTICE 'Passed: %', v_passed;
  RAISE NOTICE 'Failed: %', v_failed;
  RAISE NOTICE '============================================';

  RAISE NOTICE '';
  RAISE NOTICE 'BY CONTRACT:';
  FOR v_category_summary IN
    SELECT category,
           COUNT(*) as total,
           COUNT(*) FILTER (WHERE passed) as passed,
           COUNT(*) FILTER (WHERE NOT passed) as failed
    FROM _test_results
    GROUP BY category
    ORDER BY category
  LOOP
    RAISE NOTICE '  %: %/% passed', v_category_summary.category, v_category_summary.passed, v_category_summary.total;
  END LOOP;

  IF v_failed > 0 THEN
    RAISE NOTICE '';
    RAISE NOTICE 'FAILED TESTS:';
    FOR v_category_summary IN
      SELECT category, test_name, expected, actual, error_message
      FROM _test_results
      WHERE NOT passed
      ORDER BY category, test_name
    LOOP
      RAISE NOTICE '  [FAIL] %.%', v_category_summary.category, v_category_summary.test_name;
      RAISE NOTICE '         Expected: %', v_category_summary.expected;
      RAISE NOTICE '         Actual:   %', COALESCE(v_category_summary.actual, v_category_summary.error_message);
    END LOOP;
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '============================================';
END;
$$;

-- Return results as JSON
SELECT jsonb_pretty(jsonb_build_object(
  'summary', (
    SELECT jsonb_build_object(
      'total', COUNT(*),
      'passed', COUNT(*) FILTER (WHERE passed),
      'failed', COUNT(*) FILTER (WHERE NOT passed),
      'pass_rate', ROUND(COUNT(*) FILTER (WHERE passed)::NUMERIC / NULLIF(COUNT(*), 0) * 100, 1) || '%'
    )
    FROM _test_results
  ),
  'by_contract', (
    SELECT jsonb_agg(jsonb_build_object(
      'contract', category,
      'total', total,
      'passed', passed,
      'failed', failed
    ) ORDER BY category)
    FROM (
      SELECT category,
             COUNT(*) as total,
             COUNT(*) FILTER (WHERE passed) as passed,
             COUNT(*) FILTER (WHERE NOT passed) as failed
      FROM _test_results
      GROUP BY category
    ) t
  ),
  'failed_tests', (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'contract', category,
      'test_name', test_name,
      'expected', expected,
      'actual', actual,
      'error', error_message
    ) ORDER BY category, test_name), '[]'::jsonb)
    FROM _test_results
    WHERE NOT passed
  )
)) AS contract_test_results;

-- Cleanup: DROP TABLE IF EXISTS _test_results CASCADE;
