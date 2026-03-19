-- Migration: Prevent duplicate (interviewer, template) assignments across rounds
-- Fixes: Same interviewer assigned to multiple rounds with the same evaluation template
-- causes shared eval participant, so submitting one round marks the other as submitted too.

-- Part 1: Persist evaluation_template_id on interview_rounds
-- Nullable — existing rows without a linked eval instance can't be backfilled.
ALTER TABLE interview_rounds
  ADD COLUMN IF NOT EXISTS evaluation_template_id UUID REFERENCES evaluation_templates(id);

-- Part 2: Backfill from existing data
-- Derive template_id from the linked evaluation instance where possible.
UPDATE interview_rounds ir
SET evaluation_template_id = ei.template_id
FROM evaluation_instances ei
WHERE ei.id = ir.evaluation_instance_id
  AND ir.evaluation_template_id IS NULL;

-- Part 3: Pre-check — fail migration if existing duplicates
-- Before creating the trigger, assert no existing violations.
DO $$
DECLARE
  v_dup_count INT;
BEGIN
  SELECT count(*) INTO v_dup_count
  FROM (
    SELECT ir.interview_id, ir.evaluation_template_id, ia.user_id
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    WHERE ir.evaluation_template_id IS NOT NULL
    GROUP BY ir.interview_id, ir.evaluation_template_id, ia.user_id
    HAVING count(*) > 1
  ) dupes;

  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'MIGRATION_BLOCKED: % existing duplicate (interview, template, interviewer) assignments must be cleaned up before this migration can proceed', v_dup_count;
  END IF;
END;
$$;

-- Part 4: Trigger on interviewer_assignments (INSERT or UPDATE of user_id/round_id)
-- Fires on INSERT and on UPDATE of the two columns that could introduce duplicates.
CREATE OR REPLACE FUNCTION trg_check_duplicate_template_interviewer()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_interview_id UUID;
  v_template_id UUID;
BEGIN
  SELECT ir.interview_id, ir.evaluation_template_id
  INTO v_interview_id, v_template_id
  FROM interview_rounds ir
  WHERE ir.id = NEW.round_id
    AND ir.tenant_id = NEW.tenant_id;

  -- Skip check if template not set (legacy rows)
  IF v_template_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM interviewer_assignments ia
    JOIN interview_rounds ir ON ir.id = ia.round_id
    WHERE ir.interview_id = v_interview_id
      AND ir.evaluation_template_id = v_template_id
      AND ia.user_id = NEW.user_id
      AND ia.tenant_id = NEW.tenant_id
      AND ia.id IS DISTINCT FROM NEW.id
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_ROUND_ASSIGNMENT: Same interviewer cannot be assigned to multiple rounds with the same evaluation template'
      USING ERRCODE = '23505';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_duplicate_template_interviewer
  BEFORE INSERT OR UPDATE OF user_id, round_id ON interviewer_assignments
  FOR EACH ROW
  EXECUTE FUNCTION trg_check_duplicate_template_interviewer();

-- Part 5: Guard on interview_rounds.evaluation_template_id UPDATE
-- Prevent changing a round's template after assignments exist.
CREATE OR REPLACE FUNCTION trg_protect_round_template_change()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.evaluation_template_id IS DISTINCT FROM NEW.evaluation_template_id THEN
    IF EXISTS (
      SELECT 1 FROM interviewer_assignments ia WHERE ia.round_id = NEW.id
    ) THEN
      RAISE EXCEPTION 'TEMPLATE_LOCKED: Cannot change evaluation_template_id after interviewers are assigned'
        USING ERRCODE = 'P0009';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_protect_round_template
  BEFORE UPDATE OF evaluation_template_id ON interview_rounds
  FOR EACH ROW
  EXECUTE FUNCTION trg_protect_round_template_change();

-- Part 6: Indexes for trigger performance
CREATE INDEX IF NOT EXISTS idx_rounds_interview_template
  ON interview_rounds (interview_id, evaluation_template_id);

CREATE INDEX IF NOT EXISTS idx_assignments_round_user
  ON interviewer_assignments (round_id, user_id);

CREATE INDEX IF NOT EXISTS idx_assignments_tenant_user
  ON interviewer_assignments (tenant_id, user_id);
