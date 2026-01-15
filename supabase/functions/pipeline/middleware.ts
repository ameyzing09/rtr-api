import type { SupabaseClient } from '@supabase/supabase-js';

// Get tenant ID from JWT claims or X-Tenant-ID header
export async function getTenantIdFromAuth(
  req: Request,
  supabaseUser: SupabaseClient
): Promise<string> {
  // First try X-Tenant-ID header (for backward compatibility and local dev)
  const headerTenantId = req.headers.get('X-Tenant-ID');
  if (headerTenantId) return headerTenantId;

  // Try to get from JWT user metadata
  const { data: { user } } = await supabaseUser.auth.getUser();
  if (user?.user_metadata?.tenant_id) {
    return user.user_metadata.tenant_id;
  }

  // Try to get from user_profiles table
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

  throw new Error('Tenant context required');
}

// Get user info from JWT token
export async function getUserFromToken(
  supabaseUser: SupabaseClient
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

// Check if user can manage pipelines (ADMIN, HR)
export function canManagePipelines(role: string): boolean {
  return ['SUPERADMIN', 'ADMIN', 'HR'].includes(role);
}

// Check if user can view pipelines (ADMIN, HR, INTERVIEWER)
export function canViewPipelines(role: string): boolean {
  return ['SUPERADMIN', 'ADMIN', 'HR', 'INTERVIEWER'].includes(role);
}
