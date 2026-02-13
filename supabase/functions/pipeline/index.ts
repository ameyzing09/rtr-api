import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { corsResponse, handleError, jsonResponse } from './utils.ts';
import { canViewPipelines, getTenantIdFromAuth, getUserFromToken } from './middleware.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as pipelineHandlers from './handlers/pipelines.ts';

// Parse path, removing function name prefix
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/pipeline?\/?/, '')
    .replace(/^\/functions\/v1\/pipeline?\/?/, '')
    .replace(/\/$/, '')
    .split('/')
    .filter(Boolean);
}

// Check if request is using service role key (internal service call)
function isServiceRoleRequest(req: Request): boolean {
  const apiKey = req.headers.get('apikey') || '';
  const secretKey = Deno.env.get('SUPABASE_SECRET_KEY') ||
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
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
    // GET / - Health check endpoint
    if (method === 'GET' && fullPath === '') {
      return pipelineHandlers.healthCheck();
    }

    // ==================== PRIVATE ROUTES (Require Auth) ====================
    const supabaseAdmin = getSupabaseAdmin();
    const supabaseUser = getSupabaseClient(req);

    // Check for service role (internal service calls)
    const isServiceRole = isServiceRoleRequest(req);

    // POST /pipeline/assign - Special handling for service role calls
    if (method === 'POST' && fullPath === 'pipeline/assign') {
      if (isServiceRole) {
        // Service role call - no user authentication needed
        const ctx: HandlerContext = {
          supabaseAdmin,
          supabaseUser,
          tenantId: '', // Will be read from body
          pathParts,
          method,
          url,
          isServiceRole: true,
        };
        return await pipelineHandlers.assignPipeline(ctx, req);
      }
      // Fall through to normal user auth flow
    }

    // Get user from JWT token
    const user = await getUserFromToken(supabaseUser);
    if (!user) {
      throw new Error('Unauthorized: Invalid or missing token');
    }

    // Check if user can at least view pipelines
    if (!canViewPipelines(user.role)) {
      throw new Error('Forbidden: Insufficient permissions');
    }

    // Get tenant ID: Only SUPERADMIN can override via X-Tenant-ID header
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

    // ==================== PIPELINE ROUTES ====================

    // GET /pipeline - List pipelines
    if (method === 'GET' && fullPath === 'pipeline') {
      return await pipelineHandlers.listPipelines(ctx);
    }

    // POST /pipeline - Create pipeline
    if (method === 'POST' && fullPath === 'pipeline') {
      return await pipelineHandlers.createPipeline(ctx, req);
    }

    // POST /pipeline/assign - Assign pipeline to job (user call)
    if (method === 'POST' && fullPath === 'pipeline/assign') {
      return await pipelineHandlers.assignPipeline(ctx, req);
    }

    // GET /pipeline/job/:jobId - Get pipeline by job
    if (method === 'GET' && pathParts[0] === 'pipeline' && pathParts[1] === 'job' && pathParts[2]) {
      return await pipelineHandlers.getPipelineByJob(ctx);
    }

    // Routes with pipeline ID: /pipeline/:id
    if (pathParts[0] === 'pipeline' && pathParts[1] && pathParts[1] !== 'assign') {
      // Ensure pathParts has pipeline ID at index 1
      ctx.pathParts = pathParts;

      // GET /pipeline/:id - Get pipeline by ID
      if (method === 'GET') {
        return await pipelineHandlers.getPipeline(ctx);
      }

      // PATCH /pipeline/:id - Update pipeline
      if (method === 'PATCH') {
        return await pipelineHandlers.updatePipeline(ctx, req);
      }
    }

    return jsonResponse({
      code: 'not_found',
      message: 'Endpoint not found',
      status_code: 404,
    }, 404);
  } catch (error) {
    return handleError(error);
  }
});
