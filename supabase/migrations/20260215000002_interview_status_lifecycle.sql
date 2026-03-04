-- ============================================
-- Part 1: Add COMPLETED to CHECK constraint
-- ============================================

ALTER TABLE interviews
  DROP CONSTRAINT IF EXISTS interviews_status_check;

ALTER TABLE interviews
  ADD CONSTRAINT interviews_status_check
  CHECK (status IN ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'));

-- ============================================
-- Part 2: Trigger function using task-based counting
-- ============================================

CREATE OR REPLACE FUNCTION update_interview_status_on_submit()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_interview_ids UUID[];
  v_interview_id UUID;
  v_total_tasks INT;
  v_submitted_tasks INT;
BEGIN
  -- Only act when status changes to SUBMITTED
  IF NEW.status <> 'SUBMITTED' OR OLD.status = 'SUBMITTED' THEN
    RETURN NEW;
  END IF;

  -- Find all interviews linked to this evaluation instance
  SELECT array_agg(DISTINCT ir.interview_id) INTO v_interview_ids
  FROM interview_rounds ir
  WHERE ir.evaluation_instance_id = NEW.evaluation_id;

  IF v_interview_ids IS NULL THEN
    RETURN NEW;
  END IF;

  FOREACH v_interview_id IN ARRAY v_interview_ids
  LOOP
    -- Skip cancelled interviews
    IF EXISTS (
      SELECT 1 FROM interviews WHERE id = v_interview_id AND status = 'CANCELLED'
    ) THEN
      CONTINUE;
    END IF;

    -- Total tasks = count of interviewer_assignment rows for this interview
    SELECT count(*) INTO v_total_tasks
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    WHERE ir.interview_id = v_interview_id;

    -- Submitted tasks = assignment rows where matching participant is SUBMITTED
    SELECT count(*) INTO v_submitted_tasks
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    JOIN evaluation_participants ep
      ON ep.evaluation_id = ir.evaluation_instance_id
      AND ep.user_id = ia.user_id
    WHERE ir.interview_id = v_interview_id
      AND ep.status = 'SUBMITTED';

    -- Guard: skip if no assignments (orphaned interview)
    IF v_total_tasks = 0 THEN
      CONTINUE;
    END IF;

    -- Transition logic
    IF v_submitted_tasks = 0 THEN
      -- No submissions yet — stay PLANNED (no-op)
      NULL;
    ELSIF v_submitted_tasks < v_total_tasks THEN
      -- Partial — move to IN_PROGRESS (from PLANNED or stay IN_PROGRESS)
      UPDATE interviews
      SET status = 'IN_PROGRESS', updated_at = now()
      WHERE id = v_interview_id
        AND status = 'PLANNED';
    ELSE
      -- All done — move to COMPLETED (from PLANNED or IN_PROGRESS)
      UPDATE interviews
      SET status = 'COMPLETED', updated_at = now()
      WHERE id = v_interview_id
        AND status IN ('PLANNED', 'IN_PROGRESS');
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

-- ============================================
-- Part 3: Create trigger
-- ============================================

CREATE TRIGGER trg_update_interview_status
  AFTER UPDATE OF status ON evaluation_participants
  FOR EACH ROW
  EXECUTE FUNCTION update_interview_status_on_submit();

-- ============================================
-- Part 4: Backfill existing interviews
-- ============================================

WITH interview_task_counts AS (
  SELECT
    ir.interview_id,
    count(*) AS total_tasks,
    count(*) FILTER (
      WHERE ep.status = 'SUBMITTED'
    ) AS submitted_tasks
  FROM interviewer_assignments ia
  JOIN interview_rounds ir ON ir.id = ia.round_id
  LEFT JOIN evaluation_participants ep
    ON ep.evaluation_id = ir.evaluation_instance_id
    AND ep.user_id = ia.user_id
  GROUP BY ir.interview_id
)
UPDATE interviews i
SET status = CASE
  WHEN tc.submitted_tasks >= tc.total_tasks THEN 'COMPLETED'
  ELSE 'IN_PROGRESS'
END,
updated_at = now()
FROM interview_task_counts tc
WHERE i.id = tc.interview_id
  AND i.status NOT IN ('CANCELLED')
  AND tc.total_tasks > 0
  AND tc.submitted_tasks > 0;
