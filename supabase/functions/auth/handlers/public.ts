import type { HandlerContext } from '../types.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { getUserProfile } from '../middleware.ts';
import { formatUserResponse } from '../utils.ts';

// GET / - Health check
export function healthCheck(): Response {
  return new Response('rtr-user-auth-service: ok', { status: 200 });
}

// POST /login - Tenant user login
export async function login(ctx: HandlerContext, req: Request): Promise<Response> {
  const { email, password } = await req.json();
  const tenantId = req.headers.get('X-Tenant-Id');

  const { data, error } = await ctx.supabaseAdmin.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw new Error('Invalid credentials');

  // Get user profile
  const profile = await getUserProfile(ctx.supabaseAdmin, data.user.id);

  // Verify tenant if provided
  if (tenantId && profile.tenant_id !== tenantId) {
    throw new Error('User does not belong to this tenant');
  }

  // Get tenant branding
  const { data: settings } = await ctx.supabaseAdmin
    .from('tenant_settings')
    .select('config')
    .eq('tenant_id', profile.tenant_id)
    .single();

  // Convert expires_at from Unix timestamp to ISO string
  const expiresAt = data.session?.expires_at
    ? new Date(data.session.expires_at * 1000).toISOString()
    : new Date(Date.now() + 3600000).toISOString();

  return jsonResponse({
    Token: data.session?.access_token,
    ExpiresAt: expiresAt,
    User: formatUserResponse(data.user, profile),
    TenantBranding: settings?.config?.branding || null,
  });
}

// POST /admin/login - Superadmin login
export async function adminLogin(ctx: HandlerContext, req: Request): Promise<Response> {
  const { email, password } = await req.json();

  const { data, error } = await ctx.supabaseAdmin.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw new Error('Invalid credentials');

  // Verify superadmin role
  const profile = await getUserProfile(ctx.supabaseAdmin, data.user.id);
  if (profile.role !== 'SUPERADMIN') {
    throw new Error('Not a superadmin user');
  }

  // Convert expires_at from Unix timestamp to ISO string
  const expiresAt = data.session?.expires_at
    ? new Date(data.session.expires_at * 1000).toISOString()
    : new Date(Date.now() + 3600000).toISOString();

  return jsonResponse({
    Token: data.session?.access_token,
    ExpiresAt: expiresAt,
    User: formatUserResponse(data.user, profile),
    PlatformBranding: {
      name: 'Recrutr Platform',
      logo_url: '',
      primary_color: '#1F64F0',
      accent_color: '#0D2F81',
      navbar_title: 'Recrutr Admin',
      sidebar_title: 'Control Plane',
      sidebar_links: [],
    },
  });
}

// GET /tenant/settings - Get tenant settings (public)
export async function getTenantSettings(ctx: HandlerContext, req: Request): Promise<Response> {
  const tenantId = req.headers.get('X-Tenant-Id');
  if (!tenantId) throw new Error('Tenant context missing');

  const { data } = await ctx.supabaseAdmin
    .from('tenant_settings')
    .select('config')
    .eq('tenant_id', tenantId)
    .single();

  return jsonResponse({ config: data?.config || {} });
}
