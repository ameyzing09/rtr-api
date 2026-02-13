import type { HandlerContext } from '../types.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { requirePermission } from '../middleware.ts';
import { generateTempPassword } from '../utils.ts';

// GET /admin/users - List all users (superadmin)
export async function listAllUsers(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'sys:user:list');

  const tenantId = ctx.url.searchParams.get('tenant_id');
  const role = ctx.url.searchParams.get('role');
  const search = ctx.url.searchParams.get('search');
  const page = parseInt(ctx.url.searchParams.get('page') || '1');
  const limit = Math.min(parseInt(ctx.url.searchParams.get('limit') || '50'), 100);
  const offset = (page - 1) * limit;

  let query = ctx.supabaseAdmin
    .from('user_profiles')
    .select('*', { count: 'exact' })
    .is('deleted_at', null);

  if (tenantId) query = query.eq('tenant_id', tenantId);
  if (role) query = query.eq('role', role.toUpperCase());
  if (search) query = query.or(`name.ilike.%${search}%`);

  const { data, error, count } = await query
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw error;

  // Fetch emails from auth.users
  const { data: authUsers } = await ctx.supabaseAdmin.auth.admin.listUsers();

  // Create email lookup map
  const emailMap = new Map<string, string>(
    authUsers?.users?.map((u) => [u.id, u.email || '']) || [],
  );

  // Merge email into profiles
  const usersWithEmail = (data || []).map((profile) => ({
    ...profile,
    email: emailMap.get(profile.id) || null,
  }));

  return jsonResponse({
    users: usersWithEmail,
    total: count,
    page,
    limit,
  });
}

// GET /admin/users/:id - Get user by ID
export async function getUserById(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'sys:user:list');
  const userId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('*')
    .eq('id', userId)
    .single();
  if (error) throw new Error('User not found');

  // Fetch email from auth.users
  const { data: authUser } = await ctx.supabaseAdmin.auth.admin.getUserById(userId);

  return jsonResponse({
    ...data,
    email: authUser?.user?.email || null,
  });
}

// POST /admin/users/:id/reset-password
export async function resetUserPassword(ctx: HandlerContext, req: Request): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'sys:user:list');
  const userId = ctx.pathParts[2];
  const { new_password, force_change } = await req.json();

  if (force_change === undefined) {
    throw new Error('force_change is required');
  }

  const password = new_password || generateTempPassword();

  const { error } = await ctx.supabaseAdmin.auth.admin.updateUserById(userId, {
    password,
  });
  if (error) throw error;

  return jsonResponse({
    user_id: userId,
    temporary_password: password,
    force_password_reset: force_change,
    message: 'Password has been reset successfully',
  });
}

// POST /admin/change-password - Legacy superadmin password change
export async function legacyChangePassword(ctx: HandlerContext, req: Request): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const { user_id, tenant_id } = await req.json();

  if (!user_id || !tenant_id) {
    throw new Error('user_id and tenant_id are required');
  }

  // Verify user belongs to tenant
  const { data: profile } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('tenant_id')
    .eq('id', user_id)
    .single();

  if (!profile || profile.tenant_id !== tenant_id) {
    throw new Error('User not found in specified tenant');
  }

  const tempPassword = generateTempPassword();

  const { error } = await ctx.supabaseAdmin.auth.admin.updateUserById(user_id, {
    password: tempPassword,
  });
  if (error) throw error;

  return jsonResponse({
    temporary_password: tempPassword,
  });
}
