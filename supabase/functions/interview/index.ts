import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { corsResponse, handleError, jsonResponse, textResponse } from './utils.ts';
import { getTenantIdFromAuth, getUserFromToken, canViewInterviews, canManageInterviews } from './middleware.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as interviewHandlers from './handlers/interviews.ts';

// Parse path, removing function name prefix
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/interview\/?/, '')
    .replace(/^\/functions\/v1\/interview\/?/, '')
    .replace(/\/$/, '')
    .split('/')
    .filter(Boolean);
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
      return textResponse('rtr-interview-service: ok');
    }

    // ==================== ALL ROUTES REQUIRE AUTH ====================
    const supabaseAdmin = getSupabaseAdmin();
    const supabaseUser = getSupabaseClient(req);

    const user = await getUserFromToken(supabaseUser);
    if (!user) {
      throw new Error('Unauthorized: Invalid or missing token');
    }

    // Check if user can at least view interviews
    if (!canViewInterviews(user.role)) {
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

    // ==================== MY PENDING INTERVIEWS ====================
    // GET /my-pending - List rounds assigned to current user with pending evaluation
    if (method === 'GET' && pathParts[0] === 'my-pending') {
      return await interviewHandlers.listMyPending(ctx);
    }

    // ==================== APPLICATION-BOUND ROUTES ====================
    // Routes: /applications/:id/interviews
    if (pathParts[0] === 'applications' && pathParts[1]) {
      const action = pathParts[2];

      // POST /applications/:id/interviews - Create interview with rounds + assignments
      if (method === 'POST' && action === 'interviews') {
        if (!canManageInterviews(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await interviewHandlers.createInterview(ctx, req);
      }

      // GET /applications/:id/interviews - List all interviews for application
      if (method === 'GET' && action === 'interviews') {
        return await interviewHandlers.listInterviews(ctx);
      }
    }

    // ==================== INTERVIEW INSTANCE ROUTES ====================
    // Routes: /interviews/:id
    if (pathParts[0] === 'interviews' && pathParts[1]) {
      // GET /interviews/:id - Get interview detail
      if (method === 'GET') {
        return await interviewHandlers.getInterview(ctx);
      }

      // PATCH /interviews/:id - Update interview status (CANCEL)
      if (method === 'PATCH') {
        if (!canManageInterviews(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await interviewHandlers.updateInterview(ctx, req);
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
