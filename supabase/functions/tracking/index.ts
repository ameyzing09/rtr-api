import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { corsResponse, handleError, jsonResponse, textResponse } from './utils.ts';
import { getTenantIdFromAuth, getUserFromToken, canViewTracking, canManageTracking } from './middleware.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as stateHandlers from './handlers/state.ts';
import * as historyHandlers from './handlers/history.ts';
import * as boardHandlers from './handlers/board.ts';
import * as settingsHandlers from './handlers/settings.ts';

// Parse path, removing function name prefix
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/tracking?\/?/, '')
    .replace(/^\/functions\/v1\/tracking?\/?/, '')
    .replace(/\/$/, '')
    .split('/')
    .filter(Boolean);
}

// Check if request is using service role key (internal service call)
function isServiceRoleRequest(req: Request): boolean {
  const apiKey = req.headers.get('apikey') || '';
  const secretKey = Deno.env.get('SUPABASE_SECRET_KEY')
    || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  return apiKey === secretKey && secretKey !== '';
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

  try {
    // ==================== HEALTH CHECK (Public) ====================
    if (method === 'GET' && fullPath === '') {
      return textResponse('rtr-application-tracking-service: ok');
    }

    // ==================== ALL ROUTES REQUIRE AUTH ====================
    const supabaseAdmin = getSupabaseAdmin();
    const supabaseUser = getSupabaseClient(req);

    // Check for service role (internal service calls)
    const isServiceRole = isServiceRoleRequest(req);

    // ==================== SERVICE ROLE ROUTES ====================
    // POST /tracking/applications/:id/attach - Internal attach call
    if (method === 'POST' && pathParts[0] === 'applications' && pathParts[2] === 'attach') {
      if (isServiceRole) {
        const ctx: HandlerContext = {
          supabaseAdmin,
          supabaseUser,
          tenantId: '',  // Will be read from body
          pathParts,
          method,
          url,
          isServiceRole: true,
        };
        return await stateHandlers.attachToPipeline(ctx, req);
      }
      // Fall through to user auth
    }

    // ==================== USER AUTH REQUIRED ====================
    const user = await getUserFromToken(supabaseUser);
    if (!user) {
      throw new Error('Unauthorized: Invalid or missing token');
    }

    // Check if user can at least view tracking
    if (!canViewTracking(user.role)) {
      throw new Error('Forbidden: Insufficient permissions');
    }

    // Get tenant ID
    let tenantId: string;
    const headerTenantId = req.headers.get('X-Tenant-ID');

    if (user.role === 'SUPERADMIN' && headerTenantId) {
      tenantId = headerTenantId;
    } else {
      tenantId = user.tenantId || await getTenantIdFromAuth(req, supabaseUser);
    }

    const ctx: HandlerContext = {
      supabaseAdmin,
      supabaseUser,
      tenantId,
      userId: user.id,
      userRole: user.role,
      pathParts,
      method,
      url,
      isServiceRole: false,
    };

    // ==================== APPLICATION STATE ROUTES ====================
    // Routes: /applications/:id/...

    if (pathParts[0] === 'applications' && pathParts[1]) {
      const applicationId = pathParts[1];
      const action = pathParts[2];

      // POST /applications/:id/attach - Attach to pipeline (user call)
      if (method === 'POST' && action === 'attach') {
        if (!canManageTracking(user.role)) {
          throw new Error('Forbidden: ADMIN or HR role required');
        }
        return await stateHandlers.attachToPipeline(ctx, req);
      }

      // GET /applications/:id - Get tracking state
      if (method === 'GET' && !action) {
        return await stateHandlers.getState(ctx);
      }

      // POST /applications/:id/move - Move to different stage
      if (method === 'POST' && action === 'move') {
        if (!canManageTracking(user.role)) {
          throw new Error('Forbidden: ADMIN or HR role required');
        }
        return await stateHandlers.moveStage(ctx, req);
      }

      // PATCH /applications/:id/status - Update status
      if (method === 'PATCH' && action === 'status') {
        if (!canManageTracking(user.role)) {
          throw new Error('Forbidden: ADMIN or HR role required');
        }
        return await stateHandlers.updateStatus(ctx, req);
      }

      // GET /applications/:id/history - Get stage history
      if (method === 'GET' && action === 'history') {
        return await historyHandlers.getHistory(ctx);
      }
    }

    // ==================== PIPELINE BOARD ROUTES ====================
    // GET /pipelines/:id/board - Kanban board view
    if (method === 'GET' && pathParts[0] === 'pipelines' && pathParts[1] && pathParts[2] === 'board') {
      return await boardHandlers.getPipelineBoard(ctx);
    }

    // ==================== SETTINGS ROUTES ====================
    // Routes: /settings/statuses[/:id]

    if (pathParts[0] === 'settings' && pathParts[1] === 'statuses') {
      const statusId = pathParts[2];

      // GET /settings/statuses - List all statuses
      if (method === 'GET' && !statusId) {
        return await settingsHandlers.listStatuses(ctx);
      }

      // POST /settings/statuses - Create new status (ADMIN only)
      if (method === 'POST' && !statusId) {
        if (!canManageTracking(user.role)) {
          throw new Error('Forbidden: ADMIN role required to manage statuses');
        }
        return await settingsHandlers.createStatus(ctx, req);
      }

      // PATCH /settings/statuses/:id - Update status (ADMIN only)
      if (method === 'PATCH' && statusId) {
        if (!canManageTracking(user.role)) {
          throw new Error('Forbidden: ADMIN role required to manage statuses');
        }
        return await settingsHandlers.updateStatus(ctx, req);
      }

      // DELETE /settings/statuses/:id - Delete status (ADMIN only)
      if (method === 'DELETE' && statusId) {
        if (!canManageTracking(user.role)) {
          throw new Error('Forbidden: ADMIN role required to manage statuses');
        }
        return await settingsHandlers.deleteStatus(ctx);
      }
    }

    // ==================== 404 ====================
    return jsonResponse({
      code: 'not_found',
      message: 'Endpoint not found',
      status_code: 404,
    }, 404);

  } catch (error) {
    return handleError(error);
  }
});
