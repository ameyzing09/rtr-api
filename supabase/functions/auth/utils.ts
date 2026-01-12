import type { User } from '@supabase/supabase-js';
import type { UserProfile } from './types.ts';
import { getPermissions } from './permissions.ts';
import { jsonResponse } from '../_shared/cors.ts';

// Format user response (matches Go service - PascalCase)
export function formatUserResponse(user: User, profile: UserProfile) {
  return {
    ID: user.id,
    TenantID: profile.tenant_id || '',
    Name: profile.name,
    Email: user.email,
    Role: profile.role,
    Permissions: getPermissions(profile.role),
    ForcePasswordReset: false,
  };
}

// Generate temporary password
export function generateTempPassword(): string {
  return `Temp${Math.random().toString(36).slice(2)}!`;
}

// Handle errors with appropriate HTTP status codes
export function handleError(error: unknown): Response {
  const err = error as Error;
  let status = 400;
  let code = 'validation_error';

  if (err.message.includes('Unauthorized') || err.message.includes('Invalid or missing token')) {
    status = 401;
    code = 'unauthorized';
  } else if (err.message.includes('Forbidden') || err.message.includes('Missing permission')) {
    status = 403;
    code = 'forbidden';
  } else if (err.message.includes('not found') || err.message.includes('No rows')) {
    status = 404;
    code = 'not_found';
  } else if (err.message.includes('already exists') || err.message.includes('duplicate') || err.message.includes('unique')) {
    status = 409;
    code = 'conflict';
  } else if (err.message.includes('Invalid credentials')) {
    status = 401;
    code = 'unauthorized';
  }

  return jsonResponse({ code, message: err.message }, status);
}
