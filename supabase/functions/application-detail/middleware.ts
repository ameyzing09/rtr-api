import type { SupabaseClient } from '@supabase/supabase-js';

// Get user info from JWT token
export async function getUserFromToken(
  supabaseUser: SupabaseClient,
): Promise<{ id: string; role: string; tenantId: string | null } | null> {
  const { data: { user }, error } = await supabaseUser.auth.getUser();
  if (error || !user) return null;

  // Get role from user_profiles table
  const { data: profile } = await supabaseUser
    .from('user_profiles')
    .select('role, tenant_id')
    .eq('id', user.id)
    .single();

  return {
    id: user.id,
    role: profile?.role || user.user_metadata?.role || 'CANDIDATE',
    tenantId: profile?.tenant_id || user.user_metadata?.tenant_id || null,
  };
}

// Get tenant ID from verified sources only (JWT claims or user_profiles)
// NOTE: Unlike tracking/middleware.ts, this does NOT accept X-Tenant-ID header
// for non-SUPERADMIN users because this endpoint returns sensitive PII.
// SUPERADMIN header override is handled in index.ts before this is called.
export async function getTenantIdFromAuth(
  supabaseUser: SupabaseClient,
): Promise<string> {
  const { data: { user } } = await supabaseUser.auth.getUser();

  // Try user_profiles table first (authoritative source)
  if (user?.id) {
    const { data: profile } = await supabaseUser
      .from('user_profiles')
      .select('tenant_id')
      .eq('id', user.id)
      .single();
    if (profile?.tenant_id) {
      return profile.tenant_id;
    }
  }

  // Fallback to JWT metadata (set during signup, not client-writable for tenant_id)
  if (user?.user_metadata?.tenant_id) {
    return user.user_metadata.tenant_id;
  }

  throw new Error('Tenant context required');
}

// Check if user can view application details
// Allowed: SUPERADMIN, ADMIN, HR, INTERVIEWER
export function canViewApplicationDetail(role: string): boolean {
  return ['SUPERADMIN', 'ADMIN', 'HR', 'INTERVIEWER'].includes(role);
}

// Check if an interviewer is assigned to an application via interview assignments
export async function isInterviewerAssignedToApplication(
  supabaseAdmin: SupabaseClient,
  userId: string,
  tenantId: string,
  applicationId: string,
): Promise<boolean> {
  // Preferred: single joined query using Supabase nested !inner joins
  try {
    const { count, error } = await supabaseAdmin
      .from('interviewer_assignments')
      .select(
        'id, interview_rounds!inner(id, interviews!inner(id))',
        { count: 'exact', head: true },
      )
      .eq('user_id', userId)
      .eq('tenant_id', tenantId)
      .eq('interview_rounds.interviews.application_id', applicationId);

    if (!error) {
      return (count ?? 0) > 0;
    }

    // Nested filter syntax failed — fall through to 3-step fallback
    console.warn(
      'Nested join filter failed, using fallback query:',
      error.message,
    );
  } catch {
    console.warn('Nested join filter threw, using fallback query');
  }

  // Fallback: 3-step sequential query
  // Step 1: interviews for this application
  const { data: interviews } = await supabaseAdmin
    .from('interviews')
    .select('id')
    .eq('application_id', applicationId)
    .eq('tenant_id', tenantId);

  if (!interviews || interviews.length === 0) return false;

  const interviewIds = interviews.map((i: { id: string }) => i.id);

  // Step 2: rounds for those interviews
  const { data: rounds } = await supabaseAdmin
    .from('interview_rounds')
    .select('id')
    .eq('tenant_id', tenantId)
    .in('interview_id', interviewIds);

  if (!rounds || rounds.length === 0) return false;

  const roundIds = rounds.map((r: { id: string }) => r.id);

  // Step 3: assignments for this user in those rounds
  const { data: assignments } = await supabaseAdmin
    .from('interviewer_assignments')
    .select('id')
    .eq('user_id', userId)
    .in('round_id', roundIds)
    .limit(1);

  return (assignments?.length ?? 0) > 0;
}
