import type { SupabaseClient } from '@supabase/supabase-js';
import type { ApplicationRecord, JobRecord } from '../types.ts';

// Fetch application by ID with tenant isolation
export async function fetchApplication(
  supabaseAdmin: SupabaseClient,
  applicationId: string,
  tenantId: string,
): Promise<ApplicationRecord> {
  const { data, error } = await supabaseAdmin
    .from('applications')
    .select('id, tenant_id, job_id, applicant_name, applicant_email, applicant_phone, resume_url, cover_letter, status, created_at, updated_at')
    .eq('id', applicationId)
    .eq('tenant_id', tenantId)
    .single();

  if (error || !data) {
    throw new Error(`Application ${applicationId} not found`);
  }

  return data as ApplicationRecord;
}

// Fetch job by ID with tenant isolation
export async function fetchJob(
  supabaseAdmin: SupabaseClient,
  jobId: string,
  tenantId: string,
): Promise<JobRecord> {
  const { data, error } = await supabaseAdmin
    .from('jobs')
    .select('id, title, department, location')
    .eq('id', jobId)
    .eq('tenant_id', tenantId)
    .single();

  if (error || !data) {
    throw new Error(`Job ${jobId} not found`);
  }

  return data as JobRecord;
}
