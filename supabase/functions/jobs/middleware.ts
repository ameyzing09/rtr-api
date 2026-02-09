// Updated: 2026-01-13
import type { SupabaseClient } from '@supabase/supabase-js';

// Extract subdomain from host header (matches NestJS subdomain.util.ts)
export function extractSubdomain(host: string): string | null {
  // Remove port if present
  const hostWithoutPort = host.split(':')[0];
  const parts = hostWithoutPort.split('.');

  // Handle localhost and IP addresses
  if (hostWithoutPort === 'localhost' || /^\d+\.\d+\.\d+\.\d+$/.test(hostWithoutPort)) {
    return null;
  }

  // Ignore Supabase infrastructure domains (project ref is not a tenant subdomain)
  if (
    hostWithoutPort.endsWith('.supabase.co') ||
    hostWithoutPort.endsWith('.supabase.com') ||
    hostWithoutPort.endsWith('.supabase.in')
  ) {
    return null;
  }

  // Handle tenant.localhost (local development)
  if (parts.length === 2 && parts[1] === 'localhost') {
    return parts[0];
  }

  // Handle subdomain.domain.tld (return subdomain)
  if (parts.length >= 3) {
    return parts[0];
  }

  // No subdomain
  return null;
}

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

// Resolve tenant from subdomain (for public endpoints)
export async function resolveTenantFromHost(
  req: Request,
  supabaseAdmin: SupabaseClient
): Promise<string> {
  const host = req.headers.get('Host') || '';
  const subdomain = extractSubdomain(host);

  // If no subdomain, fallback to X-Tenant-ID for local dev/testing
  if (!subdomain) {
    const headerTenantId = req.headers.get('X-Tenant-ID');
    if (headerTenantId) {
      // Validate the tenant ID exists
      const { data: tenant, error } = await supabaseAdmin
        .from('tenants')
        .select('id')
        .eq('id', headerTenantId)
        .single();

      if (error || !tenant) {
        throw new Error('Tenant not found');
      }
      return tenant.id;
    }
    throw new Error('Could not resolve tenant');
  }

  // Look up tenant by slug
  const { data: tenant, error } = await supabaseAdmin
    .from('tenants')
    .select('id')
    .eq('slug', subdomain)
    .single();

  if (error || !tenant) {
    throw new Error('Tenant not found');
  }

  return tenant.id;
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

// Check if user has ADMIN or HR role (can manage jobs)
export function canManageJobs(role: string): boolean {
  return ['SUPERADMIN', 'ADMIN', 'HR'].includes(role);
}

// Check if user has permission to publish/unpublish jobs
export function canPublishJobs(role: string): boolean {
  return ['SUPERADMIN', 'ADMIN', 'HR'].includes(role);
}
