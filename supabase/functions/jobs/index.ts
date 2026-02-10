import { corsResponse, jsonResponse, corsHeaders } from '../_shared/cors.ts';
import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { handleError } from './utils.ts';
import {
  getTenantIdFromAuth,
  resolveTenantFromHost,
  getUserFromToken,
} from './middleware.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as jobHandlers from './handlers/jobs.ts';
import * as appHandlers from './handlers/applications.ts';
import * as publicHandlers from './handlers/public.ts';

// Parse path, removing function name prefix
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/jobs?\/?/, '')
    .replace(/^\/functions\/v1\/jobs?\/?/, '')
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

  const supabaseAdmin = getSupabaseAdmin();
  const supabaseUser = getSupabaseClient(req);

  try {
    // ==================== PUBLIC ROUTES ====================
    // Routes starting with /public/ don't require authentication
    if (pathParts[0] === 'public') {
      // Resolve tenant from subdomain or X-Tenant-ID header
      const tenantId = await resolveTenantFromHost(req, supabaseAdmin);
      const ctx: HandlerContext = {
        supabaseAdmin,
        supabaseUser,
        tenantId,
        pathParts,
        method,
        url,
      };

      // GET /public/jobs - List public jobs
      if (method === 'GET' && fullPath === 'public/jobs') {
        return await publicHandlers.listPublicJobs(ctx, req);
      }

      // POST /public/jobs/:jobId/apply - Apply to a public job
      if (method === 'POST' && pathParts[1] === 'jobs' && pathParts[2] && pathParts[3] === 'apply') {
        return await publicHandlers.applyToJob(ctx, req);
      }

      // GET /public/jobs/:id - Get public job by ID
      if (method === 'GET' && pathParts[1] === 'jobs' && pathParts[2]) {
        return await publicHandlers.getPublicJobById(ctx);
      }

      // GET /public/applications/:token - Get application status by token
      if (method === 'GET' && pathParts[1] === 'applications' && pathParts[2]) {
        return await publicHandlers.getApplicationByToken(ctx);
      }

      return jsonResponse({ code: 'not_found', message: 'Endpoint not found' }, 404);
    }

    // ==================== PRIVATE ROUTES (Require Auth) ====================
    // Get user from JWT token
    const user = await getUserFromToken(supabaseUser);
    if (!user) {
      throw new Error('Unauthorized: Invalid or missing token');
    }

    // Get tenant ID: Only SUPERADMIN can override via X-Tenant-ID header
    // Regular users MUST use their profile's tenant_id (security: prevent cross-tenant access)
    let tenantId: string;
    const headerTenantId = req.headers.get('X-Tenant-ID');

    if (user.role === 'SUPERADMIN' && headerTenantId) {
      // SUPERADMIN can switch tenant context for administration
      tenantId = headerTenantId;
    } else {
      // Regular users: enforce their profile's tenant_id
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
    };

    // ==================== JOB ROUTES ====================
    // GET /job - List jobs
    if (method === 'GET' && (fullPath === '' || fullPath === 'job')) {
      return await jobHandlers.listJobs(ctx, req);
    }

    // POST /job - Create job
    if (method === 'POST' && (fullPath === '' || fullPath === 'job')) {
      return await jobHandlers.createJob(ctx, req);
    }

    // Routes with job ID: /job/:id
    if (pathParts[0] === 'job' || (pathParts.length >= 1 && pathParts[0] !== 'applications')) {
      const jobIdPath = pathParts[0] === 'job' ? pathParts[1] : pathParts[0];
      const action = pathParts[0] === 'job' ? pathParts[2] : pathParts[1];

      // Skip if it's the applications route
      if (jobIdPath === 'applications' || pathParts[0] === 'applications') {
        // Fall through to applications routes
      } else if (jobIdPath) {
        // Normalize pathParts for handlers (ensure jobId is at index 1)
        const normalizedParts = pathParts[0] === 'job'
          ? pathParts
          : ['job', ...pathParts];
        ctx.pathParts = normalizedParts;

        // GET /job/:id/cascade-info - Get cascade deletion info
        if (method === 'GET' && action === 'cascade-info') {
          return await jobHandlers.getCascadeInfo(ctx);
        }

        // PUT /job/:id/publish - Publish job
        if (method === 'PUT' && action === 'publish') {
          return await jobHandlers.publishJob(ctx);
        }

        // PUT /job/:id/unpublish - Unpublish job
        if (method === 'PUT' && action === 'unpublish') {
          return await jobHandlers.unpublishJob(ctx);
        }

        // GET /job/:id - Get job by ID
        if (method === 'GET' && !action) {
          return await jobHandlers.getJob(ctx);
        }

        // PUT /job/:id - Update job
        if (method === 'PUT' && !action) {
          return await jobHandlers.updateJob(ctx, req);
        }

        // DELETE /job/:id - Delete job
        if (method === 'DELETE' && !action) {
          const response = await jobHandlers.deleteJob(ctx);
          // Add CORS headers to 204 response
          if (response.status === 204) {
            return new Response(null, {
              status: 204,
              headers: corsHeaders,
            });
          }
          return response;
        }
      }
    }

    // ==================== APPLICATION ROUTES ====================
    // GET /applications - List applications
    if (method === 'GET' && fullPath === 'applications') {
      return await appHandlers.listApplications(ctx, req);
    }

    // POST /applications - Create application
    if (method === 'POST' && fullPath === 'applications') {
      return await appHandlers.createApplication(ctx, req);
    }

    // Routes with application ID: /applications/:id
    if (pathParts[0] === 'applications' && pathParts[1]) {
      // GET /applications/:id
      if (method === 'GET') {
        return await appHandlers.getApplication(ctx);
      }

      // PUT /applications/:id
      if (method === 'PUT') {
        return await appHandlers.updateApplication(ctx, req);
      }

      // DELETE /applications/:id
      if (method === 'DELETE') {
        const response = await appHandlers.deleteApplication(ctx);
        // Add CORS headers to 204 response
        if (response.status === 204) {
          return new Response(null, {
            status: 204,
            headers: corsHeaders,
          });
        }
        return response;
      }
    }

    return jsonResponse({ code: 'not_found', message: 'Endpoint not found' }, 404);
  } catch (error) {
    return handleError(error);
  }
});
