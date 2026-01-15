-- Backfill: Assign default pipeline to all existing jobs without assignments
-- This ensures all existing ACTIVE jobs have a pipeline assigned

INSERT INTO pipeline_assignments (tenant_id, pipeline_id, job_id, is_deleted)
SELECT
  j.tenant_id,
  '00000000-0000-0000-0000-000000000100',  -- Default Hiring Pipeline
  j.id,
  false
FROM jobs j
WHERE NOT EXISTS (
  SELECT 1 FROM pipeline_assignments pa WHERE pa.job_id = j.id
);
