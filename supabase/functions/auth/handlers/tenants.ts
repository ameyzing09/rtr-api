import type { HandlerContext } from '../types.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { requirePermission } from '../middleware.ts';
import { generateTempPassword } from '../utils.ts';

// GET /admin/tenants - List all tenants
export async function listTenants(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:list');

  const page = parseInt(ctx.url.searchParams.get('page') || '1');
  const size = Math.min(parseInt(ctx.url.searchParams.get('size') || '20'), 100);
  const offset = (page - 1) * size;

  const { data, error, count } = await ctx.supabaseAdmin
    .from('tenants')
    .select('*', { count: 'exact' })
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .range(offset, offset + size - 1);
  if (error) throw error;

  return jsonResponse({
    tenants: data,
    total: count,
    page,
    page_size: size,
  });
}

// POST /admin/tenant/create - Create tenant
export async function createTenant(ctx: HandlerContext, req: Request): Promise<Response> {
  const { user } = await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:create');
  const { name, domain, admin_name, admin_email, plan, is_trial } = await req.json();

  if (!name || !admin_name || !admin_email) {
    throw new Error('name, admin_name, and admin_email are required');
  }

  // Create tenant
  const slug = name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
  const { data: tenant, error: tenantError } = await ctx.supabaseAdmin
    .from('tenants')
    .insert({
      name,
      domain: domain || null,
      slug,
      plan: plan || 'STARTER',
      status: 'PENDING',
      created_by: user.id,
    })
    .select()
    .single();
  if (tenantError) {
    if (tenantError.message.includes('duplicate') || tenantError.message.includes('unique')) {
      throw new Error('Tenant name or domain already exists');
    }
    throw tenantError;
  }

  // Create admin user
  const tempPassword = generateTempPassword();
  const { error: adminError } = await ctx.supabaseAdmin.auth.admin.createUser({
    email: admin_email,
    password: tempPassword,
    email_confirm: true,
    user_metadata: {
      full_name: admin_name,
      tenant_id: tenant.id,
      role: 'ADMIN',
    },
  });
  if (adminError) throw adminError;

  // Create tenant settings
  await ctx.supabaseAdmin.from('tenant_settings').insert({
    tenant_id: tenant.id,
    config: { branding: { name } },
  });

  // Create subscription
  await ctx.supabaseAdmin.from('subscriptions').insert({
    tenant_id: tenant.id,
    plan: plan || 'STARTER',
    status: is_trial ? 'TRIAL' : 'ACTIVE',
    trial_ends_at: is_trial ? new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString() : null,
  });

  // Update tenant status
  await ctx.supabaseAdmin.from('tenants').update({ status: 'ACTIVE' }).eq('id', tenant.id);

  return jsonResponse({
    tenant: {
      id: tenant.id,
      name: tenant.name,
      domain: tenant.domain,
      slug: tenant.slug,
      plan: tenant.plan,
      status: 'ACTIVE',
    },
    temp_password: tempPassword,
    status: 'ACTIVE',
  }, 201);
}

// GET /admin/tenant/:id - Get tenant details
export async function getTenant(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:read');
  const tenantId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('tenants')
    .select('*')
    .eq('id', tenantId)
    .single();
  if (error) throw new Error('Tenant not found');

  return jsonResponse(data);
}

// PUT /admin/tenant/:id - Update tenant
export async function updateTenant(ctx: HandlerContext, req: Request): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const tenantId = ctx.pathParts[2];
  const updates = await req.json();

  // Only allow specific fields
  const allowedFields = ['name', 'domain', 'plan', 'status'] as const;
  const filteredUpdates: Record<string, string | null> = {};
  for (const key of allowedFields) {
    if (updates[key] !== undefined) {
      filteredUpdates[key] = updates[key];
    }
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('tenants')
    .update({ ...filteredUpdates, updated_at: new Date().toISOString() })
    .eq('id', tenantId)
    .select()
    .single();
  if (error) throw error;

  return jsonResponse(data);
}

// DELETE /admin/tenant/:id - Delete tenant (soft delete)
export async function deleteTenant(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const tenantId = ctx.pathParts[2];

  const { error } = await ctx.supabaseAdmin
    .from('tenants')
    .update({
      status: 'DELETED',
      deleted_at: new Date().toISOString(),
    })
    .eq('id', tenantId);
  if (error) throw error;

  return jsonResponse({ success: true }, 204);
}

// GET /tenant/:id/status - Get tenant status
export async function getTenantStatus(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:status');
  const tenantId = ctx.pathParts[1];

  const { data, error } = await ctx.supabaseAdmin
    .from('tenants')
    .select('status')
    .eq('id', tenantId)
    .single();
  if (error) throw new Error('Tenant not found');

  return jsonResponse({
    status: data.status,
    steps: ['Tenant created', 'Admin user created', 'Settings initialized', 'Subscription created'],
  });
}

// POST /tenant/:id/retry - Retry provisioning
export async function retryProvisioning(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:status');
  const tenantId = ctx.pathParts[1];

  const { data: tenant } = await ctx.supabaseAdmin
    .from('tenants')
    .select('status')
    .eq('id', tenantId)
    .single();

  if (tenant?.status !== 'FAILED') {
    throw new Error('Tenant is not in FAILED status');
  }

  await ctx.supabaseAdmin
    .from('tenants')
    .update({ status: 'PROVISIONING' })
    .eq('id', tenantId);

  return jsonResponse({ success: true }, 202);
}

// GET /admin/tenants/archived - List archived tenants
export async function listArchivedTenants(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:list');

  const page = parseInt(ctx.url.searchParams.get('page') || '1');
  const pageSize = Math.min(parseInt(ctx.url.searchParams.get('page_size') || '20'), 100);
  const offset = (page - 1) * pageSize;

  const { data, error, count } = await ctx.supabaseAdmin
    .from('tenants')
    .select('*', { count: 'exact' })
    .eq('status', 'DELETED')
    .not('deleted_at', 'is', null)
    .order('deleted_at', { ascending: false })
    .range(offset, offset + pageSize - 1);
  if (error) throw error;

  return jsonResponse({
    archives: data,
    total: count,
    page,
    page_size: pageSize,
  });
}

// GET /admin/tenant/:id/archived - Get archived tenant
export async function getArchivedTenant(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:read');
  const tenantId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('tenants')
    .select('*')
    .eq('id', tenantId)
    .eq('status', 'DELETED')
    .single();
  if (error) throw new Error('Archived tenant not found');

  return jsonResponse(data);
}
