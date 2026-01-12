import type { SupabaseClient, User } from '@supabase/supabase-js';
import type { UserProfile, AuthContext } from './types.ts';
import { getPermissions, hasPermission } from './permissions.ts';

// Get authenticated user from JWT
export async function getUser(supabaseUser: SupabaseClient): Promise<User> {
  const { data: { user }, error } = await supabaseUser.auth.getUser();
  if (error || !user) throw new Error('Unauthorized: Invalid or missing token');
  return user;
}

// Get user profile with role from database
export async function getUserProfile(
  supabaseAdmin: SupabaseClient,
  userId: string
): Promise<UserProfile> {
  const { data, error } = await supabaseAdmin
    .from('user_profiles')
    .select('*')
    .eq('id', userId)
    .single();
  if (error || !data) throw new Error('User profile not found');
  return data as UserProfile;
}

// Require authentication (any logged-in user)
export async function requireAuth(
  supabaseUser: SupabaseClient,
  supabaseAdmin: SupabaseClient
): Promise<AuthContext> {
  const user = await getUser(supabaseUser);
  const profile = await getUserProfile(supabaseAdmin, user.id);
  const permissions = getPermissions(profile.role);
  return { user, profile, permissions };
}

// Require specific permission
export async function requirePermission(
  supabaseUser: SupabaseClient,
  supabaseAdmin: SupabaseClient,
  permission: string
): Promise<AuthContext> {
  const ctx = await requireAuth(supabaseUser, supabaseAdmin);
  if (!hasPermission(ctx.permissions, permission)) {
    throw new Error(`Forbidden: Missing permission ${permission}`);
  }
  return ctx;
}

// Require SUPERADMIN role
export async function requireSuperadmin(
  supabaseUser: SupabaseClient,
  supabaseAdmin: SupabaseClient
): Promise<AuthContext> {
  const ctx = await requireAuth(supabaseUser, supabaseAdmin);
  if (ctx.profile.role !== 'SUPERADMIN') {
    throw new Error('Forbidden: Superadmin access required');
  }
  return ctx;
}
