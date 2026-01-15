-- Add status column to jobs table
-- States: DRAFT → ACTIVE → ARCHIVED
-- DRAFT: Job created, no pipeline assigned yet
-- ACTIVE: Pipeline assigned, job is valid
-- ARCHIVED: Job closed/deleted

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'DRAFT';

-- Create index for status queries
CREATE INDEX IF NOT EXISTS idx_jobs_status ON public.jobs(status);

-- Update existing jobs to ACTIVE (they already exist and work)
UPDATE public.jobs SET status = 'ACTIVE' WHERE status IS NULL OR status = 'DRAFT';
