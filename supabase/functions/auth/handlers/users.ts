import type { HandlerContext } from '../types.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { requirePermission } from '../middleware.ts';
import { getPermissions } from '../permissions.ts';
import { generateTempPassword } from '../utils.ts';

// GET /users - List tenant users
export async function listTenantUsers(ctx: HandlerContext): Promise<Response> {
  const { profile } = await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'member:*');

  const { data, error } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('*')
    .eq('tenant_id', profile.tenant_id)
    .is('deleted_at', null);
  if (error) throw error;

  // Add permissions to each user
  const users = data.map((u) => ({
    ...u,
    permissions: getPermissions(u.role),
  }));

  return jsonResponse(users);
}

// POST /users - Create tenant user
export async function createTenantUser(ctx: HandlerContext, req: Request): Promise<Response> {
  const { profile } = await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'member:*');
  const { email, name, role } = await req.json();

  if (!email || !name || !role) {
    throw new Error('email, name, and role are required');
  }

  const upperRole = role.toUpperCase();
  if (!['ADMIN', 'HR', 'INTERVIEWER', 'CANDIDATE'].includes(upperRole)) {
    throw new Error('Invalid role. Must be: admin, hr, interviewer, or candidate');
  }

  const tempPassword = generateTempPassword();

  // Create auth user
  const { data: authData, error: authError } = await ctx.supabaseAdmin.auth.admin.createUser({
    email,
    password: tempPassword,
    email_confirm: true,
    user_metadata: {
      full_name: name,
      tenant_id: profile.tenant_id,
      role: upperRole,
    },
  });
  if (authError) {
    if (authError.message.includes('already')) {
      throw new Error('Email already exists in this tenant');
    }
    throw authError;
  }

  // Update profile (trigger creates it, we update role/name)
  const { data: userProfile } = await ctx.supabaseAdmin
    .from('user_profiles')
    .update({ role: upperRole, name })
    .eq('id', authData.user.id)
    .select()
    .single();

  return jsonResponse({
    user: {
      id: authData.user.id,
      tenant_id: profile.tenant_id,
      name,
      email,
      role: upperRole,
      permissions: getPermissions(upperRole),
      force_password_reset: true,
      created_at: userProfile?.created_at || new Date().toISOString(),
      updated_at: userProfile?.updated_at || new Date().toISOString(),
    },
    temporary_password: tempPassword,
  }, 201);
}

// PATCH /users/:id - Update tenant user (role, active status)
export async function updateTenantUser(ctx: HandlerContext, req: Request): Promise<Response> {
  const { profile } = await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'member:*');
  const userId = ctx.pathParts[1];
  const { role, is_active } = await req.json();

  // Verify target user belongs to same tenant
  const { data: targetUser, error: fetchError } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('*')
    .eq('id', userId)
    .eq('tenant_id', profile.tenant_id)
    .is('deleted_at', null)
    .single();
  if (fetchError || !targetUser) throw new Error('User not found');

  const updateData: Record<string, unknown> = {};

  if (role !== undefined) {
    const upperRole = role.toUpperCase();
    if (!['ADMIN', 'HR', 'INTERVIEWER', 'CANDIDATE'].includes(upperRole)) {
      throw new Error('Invalid role. Must be: admin, hr, interviewer, or candidate');
    }
    updateData.role = upperRole;

    // Sync role to auth user_metadata so JWT stays consistent
    await ctx.supabaseAdmin.auth.admin.updateUserById(userId, {
      user_metadata: { role: upperRole },
    });
  }

  if (is_active !== undefined) {
    updateData.is_active = is_active;
  }

  if (Object.keys(updateData).length === 0) {
    throw new Error('No fields to update. Provide role or is_active.');
  }

  updateData.updated_at = new Date().toISOString();

  const { data: updated, error: updateError } = await ctx.supabaseAdmin
    .from('user_profiles')
    .update(updateData)
    .eq('id', userId)
    .eq('tenant_id', profile.tenant_id)
    .select()
    .single();
  if (updateError) throw updateError;

  return jsonResponse({
    user: { ...updated, permissions: getPermissions(updated.role) },
  });
}

// POST /users/:id/reset-password - Reset tenant user password
export async function resetTenantUserPassword(ctx: HandlerContext, req: Request): Promise<Response> {
  const { profile } = await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'member:*');
  const userId = ctx.pathParts[1];
  const { new_password, force_change } = await req.json();

  if (force_change === undefined) {
    throw new Error('force_change is required');
  }

  // Verify target user belongs to same tenant
  const { data: targetUser, error: fetchError } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('tenant_id')
    .eq('id', userId)
    .eq('tenant_id', profile.tenant_id)
    .is('deleted_at', null)
    .single();
  if (fetchError || !targetUser) throw new Error('User not found');

  const password = new_password || generateTempPassword();

  const { error } = await ctx.supabaseAdmin.auth.admin.updateUserById(userId, { password });
  if (error) throw error;

  // Update force_password_reset flag
  await ctx.supabaseAdmin
    .from('user_profiles')
    .update({ force_password_reset: force_change, updated_at: new Date().toISOString() })
    .eq('id', userId);

  return jsonResponse({
    user_id: userId,
    temporary_password: password,
    force_password_reset: force_change,
    message: 'Password has been reset successfully',
  });
}

// PUT /tenant/settings - Update tenant settings
export async function updateTenantSettings(ctx: HandlerContext, req: Request): Promise<Response> {
  const { profile } = await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'settings:*');
  const { config } = await req.json();

  const { data, error } = await ctx.supabaseAdmin
    .from('tenant_settings')
    .upsert({
      tenant_id: profile.tenant_id,
      config,
      updated_at: new Date().toISOString(),
    })
    .select()
    .single();
  if (error) throw error;

  return jsonResponse({ config: data.config });
}
