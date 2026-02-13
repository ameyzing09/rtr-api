import { corsResponse, jsonResponse } from '../_shared/cors.ts';
import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { handleError } from './utils.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as publicHandlers from './handlers/public.ts';
import * as profileHandlers from './handlers/profile.ts';
import * as userHandlers from './handlers/users.ts';
import * as tenantHandlers from './handlers/tenants.ts';
import * as subscriptionHandlers from './handlers/subscriptions.ts';
import * as adminHandlers from './handlers/admin.ts';

// Parse URL path into clean parts
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/auth\/?/, '')
    .replace(/^\/functions\/v1\/auth\/?/, '')
    .replace(/\/$/, '')
    .split('/').filter(Boolean);
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  const url = new URL(req.url);
  const pathParts = parsePath(req.url);
  const fullPath = pathParts.join('/');
  const method = req.method;

  // Build handler context
  const ctx: HandlerContext = {
    supabaseAdmin: getSupabaseAdmin(),
    supabaseUser: getSupabaseClient(req),
    url,
    pathParts,
    method,
  };

  try {
    // ==================== PUBLIC ROUTES ====================

    // GET / - Health check
    if (method === 'GET' && fullPath === '') {
      return publicHandlers.healthCheck();
    }

    // POST /login - Tenant user login
    if (method === 'POST' && fullPath === 'login') {
      return await publicHandlers.login(ctx, req);
    }

    // POST /admin/login - Superadmin login
    if (method === 'POST' && fullPath === 'admin/login') {
      return await publicHandlers.adminLogin(ctx, req);
    }

    // GET /tenant/settings - Get tenant settings (public)
    if (method === 'GET' && fullPath === 'tenant/settings') {
      return await publicHandlers.getTenantSettings(ctx, req);
    }

    // ==================== PROFILE ROUTES ====================

    // POST /logout or /admin/logout
    if (method === 'POST' && (fullPath === 'logout' || fullPath === 'admin/logout')) {
      return profileHandlers.logout();
    }

    // GET /me - Get current user profile
    if (method === 'GET' && fullPath === 'me') {
      return await profileHandlers.getMe(ctx);
    }

    // POST /me/change-password
    if (method === 'POST' && fullPath === 'me/change-password') {
      return await profileHandlers.changePassword(ctx, req);
    }

    // ==================== USER ROUTES ====================

    // GET /users - List tenant users
    if (method === 'GET' && fullPath === 'users') {
      return await userHandlers.listTenantUsers(ctx);
    }

    // POST /users - Create tenant user
    if (method === 'POST' && fullPath === 'users') {
      return await userHandlers.createTenantUser(ctx, req);
    }

    // PATCH /users/:id - Update tenant user
    if (method === 'PATCH' && pathParts[0] === 'users' && pathParts.length === 2) {
      return await userHandlers.updateTenantUser(ctx, req);
    }

    // POST /users/:id/reset-password - Reset tenant user password
    if (method === 'POST' && pathParts[0] === 'users' && pathParts[2] === 'reset-password' && pathParts.length === 3) {
      return await userHandlers.resetTenantUserPassword(ctx, req);
    }

    // PUT /tenant/settings - Update tenant settings
    if (method === 'PUT' && fullPath === 'tenant/settings') {
      return await userHandlers.updateTenantSettings(ctx, req);
    }

    // ==================== TENANT ROUTES ====================

    // GET /admin/tenants - List all tenants
    if (method === 'GET' && fullPath === 'admin/tenants') {
      return await tenantHandlers.listTenants(ctx);
    }

    // POST /admin/tenant/create - Create tenant
    if (method === 'POST' && fullPath === 'admin/tenant/create') {
      return await tenantHandlers.createTenant(ctx, req);
    }

    // GET /admin/tenants/archived - List archived tenants
    if (method === 'GET' && fullPath === 'admin/tenants/archived') {
      return await tenantHandlers.listArchivedTenants(ctx);
    }

    // GET /admin/tenant/:id/archived - Get archived tenant
    if (
      method === 'GET' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts[3] === 'archived' &&
      pathParts.length === 4
    ) {
      return await tenantHandlers.getArchivedTenant(ctx);
    }

    // GET /admin/tenant/:id - Get tenant details
    if (method === 'GET' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts.length === 3) {
      return await tenantHandlers.getTenant(ctx);
    }

    // PUT /admin/tenant/:id - Update tenant
    if (method === 'PUT' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts.length === 3) {
      return await tenantHandlers.updateTenant(ctx, req);
    }

    // DELETE /admin/tenant/:id - Delete tenant
    if (method === 'DELETE' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts.length === 3) {
      return await tenantHandlers.deleteTenant(ctx);
    }

    // GET /tenant/:id/status - Get tenant status
    if (method === 'GET' && pathParts[0] === 'tenant' && pathParts[2] === 'status' && pathParts.length === 3) {
      return await tenantHandlers.getTenantStatus(ctx);
    }

    // POST /tenant/:id/retry - Retry provisioning
    if (method === 'POST' && pathParts[0] === 'tenant' && pathParts[2] === 'retry' && pathParts.length === 3) {
      return await tenantHandlers.retryProvisioning(ctx);
    }

    // ==================== SUBSCRIPTION ROUTES ====================

    // GET /admin/tenant/:id/subscription - Get subscription
    if (
      method === 'GET' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts[3] === 'subscription' &&
      pathParts.length === 4
    ) {
      return await subscriptionHandlers.getSubscription(ctx);
    }

    // POST /admin/tenant/:id/subscription/activate
    if (
      method === 'POST' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts[3] === 'subscription' &&
      pathParts[4] === 'activate'
    ) {
      return await subscriptionHandlers.activateSubscription(ctx, req);
    }

    // POST /admin/tenant/:id/subscription/suspend
    if (
      method === 'POST' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts[3] === 'subscription' &&
      pathParts[4] === 'suspend'
    ) {
      return await subscriptionHandlers.suspendSubscription(ctx);
    }

    // POST /admin/tenant/:id/subscription/resume
    if (
      method === 'POST' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts[3] === 'subscription' &&
      pathParts[4] === 'resume'
    ) {
      return await subscriptionHandlers.resumeSubscription(ctx);
    }

    // POST /admin/tenant/:id/subscription/cancel
    if (
      method === 'POST' && pathParts[0] === 'admin' && pathParts[1] === 'tenant' && pathParts[3] === 'subscription' &&
      pathParts[4] === 'cancel'
    ) {
      return await subscriptionHandlers.cancelSubscription(ctx);
    }

    // ==================== ADMIN ROUTES ====================

    // GET /admin/users - List all users
    if (method === 'GET' && fullPath === 'admin/users') {
      return await adminHandlers.listAllUsers(ctx);
    }

    // POST /admin/change-password - Legacy password change
    if (method === 'POST' && fullPath === 'admin/change-password') {
      return await adminHandlers.legacyChangePassword(ctx, req);
    }

    // GET /admin/users/:id - Get user by ID
    if (method === 'GET' && pathParts[0] === 'admin' && pathParts[1] === 'users' && pathParts.length === 3) {
      return await adminHandlers.getUserById(ctx);
    }

    // POST /admin/users/:id/reset-password
    if (
      method === 'POST' && pathParts[0] === 'admin' && pathParts[1] === 'users' && pathParts[3] === 'reset-password'
    ) {
      return await adminHandlers.resetUserPassword(ctx, req);
    }

    // 404 - Not found
    return jsonResponse({ code: 'not_found', message: 'Endpoint not found' }, 404);
  } catch (error) {
    return handleError(error);
  }
});
