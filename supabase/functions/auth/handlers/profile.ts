import type { HandlerContext } from '../types.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { requireAuth } from '../middleware.ts';
import { formatUserResponse } from '../utils.ts';

// POST /logout or /admin/logout
export function logout(): Response {
  return jsonResponse({ success: true }, 204);
}

// GET /me - Get current user profile
export async function getMe(ctx: HandlerContext): Promise<Response> {
  const { user, profile } = await requireAuth(ctx.supabaseUser, ctx.supabaseAdmin);
  return jsonResponse(formatUserResponse(user, profile));
}

// POST /me/change-password
export async function changePassword(ctx: HandlerContext, req: Request): Promise<Response> {
  const { user } = await requireAuth(ctx.supabaseUser, ctx.supabaseAdmin);
  const { current_password, new_password } = await req.json();

  if (!current_password || !new_password) {
    throw new Error('current_password and new_password are required');
  }
  if (new_password.length < 6) {
    throw new Error('Password must be at least 6 characters');
  }

  // Verify current password
  const { error: verifyError } = await ctx.supabaseAdmin.auth.signInWithPassword({
    email: user.email!,
    password: current_password,
  });
  if (verifyError) throw new Error('Invalid current password');

  // Update password
  const { error } = await ctx.supabaseAdmin.auth.admin.updateUserById(user.id, {
    password: new_password,
  });
  if (error) throw error;

  return jsonResponse({ success: true }, 204);
}
