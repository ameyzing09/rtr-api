import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { corsResponse, handleError, jsonResponse, textResponse } from './utils.ts';
import { canViewApplicationDetail, getTenantIdFromAuth, getUserFromToken } from './middleware.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as detailHandlers from './handlers/detail.ts';

// Parse path, removing function name prefix
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/application-detail?\/?/, '')
    .replace(/^\/functions\/v1\/application-detail?\/?/, '')
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
      return textResponse('rtr-application-detail-service: ok');
    }

    // ==================== ALL ROUTES REQUIRE AUTH ====================
    const supabaseAdmin = getSupabaseAdmin();
    const supabaseUser = getSupabaseClient(req);

    const user = await getUserFromToken(supabaseUser);
    if (!user) {
      throw new Error('Unauthorized: Invalid or missing token');
    }

    // Check role-based access
    if (!canViewApplicationDetail(user.role)) {
      throw new Error('Forbidden: Insufficient permissions');
    }

    // Get tenant ID
    let tenantId: string;
    const headerTenantId = req.headers.get('X-Tenant-ID');

    if (user.role === 'SUPERADMIN' && headerTenantId) {
      tenantId = headerTenantId;
    } else {
      tenantId = user.tenantId || await getTenantIdFromAuth(supabaseUser);
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
    };

    // ==================== APPLICATION DETAIL ROUTES ====================
    // GET /applications/:id - Get full application detail
    if (method === 'GET' && pathParts[0] === 'applications' && pathParts[1] && !pathParts[2]) {
      return await detailHandlers.getApplicationDetail(ctx);
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
