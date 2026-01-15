-- REVERT & FIX: Global default pipeline architecture
-- Correct model: ONE global default pipeline (tenant_id = NULL, is_default = true)
-- Tenants create their own pipelines from scratch (tenant_id = X)
-- Cloning is optional, not mandatory

-- 1. Delete all incorrectly created per-tenant pipelines
DELETE FROM public.pipelines
WHERE name = 'Default Hiring Pipeline' AND tenant_id IS NOT NULL;

-- 2. Drop the incorrect trigger and function
DROP TRIGGER IF EXISTS on_tenant_created_add_pipeline ON public.tenants;
DROP FUNCTION IF EXISTS public.create_default_pipeline_for_tenant();

-- 3. Alter pipelines table for global default support
ALTER TABLE public.pipelines
  ALTER COLUMN tenant_id DROP NOT NULL;

ALTER TABLE public.pipelines
  ADD COLUMN IF NOT EXISTS is_default BOOLEAN DEFAULT FALSE;

-- 4. Create ONE global default pipeline (read-only template)
INSERT INTO public.pipelines (
  id,
  tenant_id,
  name,
  description,
  stages,
  is_active,
  is_deleted,
  is_default
)
VALUES (
  '00000000-0000-0000-0000-000000000100',
  NULL,
  'Default Hiring Pipeline',
  'Standard recruitment workflow template. Tenants can use this as reference or create their own.',
  '[
    {"stage": "Applied", "type": "screening", "conducted_by": "HR"},
    {"stage": "Phone Screen", "type": "interview", "conducted_by": "HR"},
    {"stage": "Technical Interview", "type": "interview", "conducted_by": "Hiring Manager"},
    {"stage": "Final Interview", "type": "interview", "conducted_by": "Panel"},
    {"stage": "Offer", "type": "decision", "conducted_by": "HR"},
    {"stage": "Hired", "type": "outcome", "conducted_by": "HR"}
  ]'::JSONB,
  TRUE,
  FALSE,
  TRUE
)
ON CONFLICT (id) DO NOTHING;
