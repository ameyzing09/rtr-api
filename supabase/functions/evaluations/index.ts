import { getSupabaseAdmin, getSupabaseClient } from '../_shared/supabase.ts';
import { corsResponse, handleError, jsonResponse, textResponse } from './utils.ts';
import { getTenantIdFromAuth, getUserFromToken, canViewEvaluations, canManageEvaluations, canManageSettings } from './middleware.ts';
import type { HandlerContext } from './types.ts';

// Import handlers
import * as templateHandlers from './handlers/templates.ts';
import * as instanceHandlers from './handlers/instances.ts';
import * as participantHandlers from './handlers/participants.ts';
import * as responseHandlers from './handlers/responses.ts';
import * as signalHandlers from './handlers/signals.ts';
import * as auditHandlers from './handlers/audit.ts';

// Parse path, removing function name prefix
function parsePath(url: string): string[] {
  return new URL(url).pathname
    .replace(/^\/evaluations?\/?/, '')
    .replace(/^\/functions\/v1\/evaluations?\/?/, '')
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
      return textResponse('rtr-evaluation-service: ok');
    }

    // ==================== ALL ROUTES REQUIRE AUTH ====================
    const supabaseAdmin = getSupabaseAdmin();
    const supabaseUser = getSupabaseClient(req);

    const user = await getUserFromToken(supabaseUser);
    if (!user) {
      throw new Error('Unauthorized: Invalid or missing token');
    }

    // Check if user can at least view evaluations
    if (!canViewEvaluations(user.role)) {
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

    // ==================== SETTINGS ROUTES ====================
    // Routes: /settings/evaluation-templates[/:id]
    if (pathParts[0] === 'settings' && pathParts[1] === 'evaluation-templates') {
      const templateId = pathParts[2];

      // GET /settings/evaluation-templates - List templates
      if (method === 'GET' && !templateId) {
        return await templateHandlers.listEvaluationTemplates(ctx);
      }

      // POST /settings/evaluation-templates - Create template (ADMIN only)
      if (method === 'POST' && !templateId) {
        if (!canManageSettings(user.role)) {
          throw new Error('Forbidden: ADMIN role required');
        }
        return await templateHandlers.createEvaluationTemplate(ctx, req);
      }

      // PATCH /settings/evaluation-templates/:id - Update template (ADMIN only)
      if (method === 'PATCH' && templateId) {
        if (!canManageSettings(user.role)) {
          throw new Error('Forbidden: ADMIN role required');
        }
        return await templateHandlers.updateEvaluationTemplate(ctx, req);
      }

      // DELETE /settings/evaluation-templates/:id - Delete template (ADMIN only)
      if (method === 'DELETE' && templateId) {
        if (!canManageSettings(user.role)) {
          throw new Error('Forbidden: ADMIN role required');
        }
        return await templateHandlers.deleteEvaluationTemplate(ctx);
      }
    }

    // ==================== APPLICATION-BOUND ROUTES ====================
    // Routes: /applications/:id/...
    if (pathParts[0] === 'applications' && pathParts[1]) {
      const _applicationId = pathParts[1]; // Used via ctx.pathParts in handlers
      const action = pathParts[2];

      // GET /applications/:id/evaluations - List evaluations for application
      if (method === 'GET' && action === 'evaluations') {
        return await instanceHandlers.listApplicationEvaluations(ctx);
      }

      // POST /applications/:id/evaluations - Create new evaluation
      if (method === 'POST' && action === 'evaluations') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await instanceHandlers.createEvaluation(ctx, req);
      }

      // ==================== SIGNAL ROUTES ====================
      // GET /applications/:id/signals - Get application signals
      if (method === 'GET' && action === 'signals' && !pathParts[3]) {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await signalHandlers.getApplicationSignals(ctx);
      }

      // POST /applications/:id/signals - Set manual signal (ADMIN only)
      if (method === 'POST' && action === 'signals') {
        if (!canManageSettings(user.role)) {
          throw new Error('Forbidden: ADMIN role required');
        }
        return await signalHandlers.setManualSignal(ctx, req);
      }

      // GET /applications/:id/signals/:key/history - Signal history
      if (method === 'GET' && action === 'signals' && pathParts[3] && pathParts[4] === 'history') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await signalHandlers.getSignalHistory(ctx);
      }

      // ==================== AUDIT ROUTES ====================
      // GET /applications/:id/decision-log - Get decision audit log
      if (method === 'GET' && action === 'decision-log') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        // Check if there's a log entry ID
        if (pathParts[3]) {
          return await auditHandlers.getDecisionLogEntry(ctx);
        }
        return await auditHandlers.getDecisionLog(ctx);
      }

      // GET /applications/:id/rejection-reason - Quick rejection reason
      if (method === 'GET' && action === 'rejection-reason') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await auditHandlers.getRejectionReason(ctx);
      }
    }

    // ==================== EVALUATION INSTANCE ROUTES ====================
    // Routes: /evaluations/:id/...
    if (pathParts[0] === 'evaluations' && pathParts[1]) {
      const _evaluationId = pathParts[1]; // Used via ctx.pathParts in handlers
      const evalAction = pathParts[2];

      // POST /evaluations/:id/cancel - Cancel evaluation
      if (method === 'POST' && evalAction === 'cancel') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await instanceHandlers.cancelEvaluation(ctx);
      }

      // POST /evaluations/:id/complete - Complete evaluation
      if (method === 'POST' && evalAction === 'complete') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await instanceHandlers.completeEvaluation(ctx, req);
      }

      // GET /evaluations/:id/participants - List participants
      if (method === 'GET' && evalAction === 'participants') {
        return await participantHandlers.listParticipants(ctx);
      }

      // POST /evaluations/:id/participants - Add participant
      if (method === 'POST' && evalAction === 'participants') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await participantHandlers.addParticipant(ctx, req);
      }

      // DELETE /evaluations/:id/participants/:participantId - Remove participant
      if (method === 'DELETE' && evalAction === 'participants' && pathParts[3]) {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await participantHandlers.removeParticipant(ctx);
      }

      // POST /evaluations/:id/respond - Submit response (evaluator)
      if (method === 'POST' && evalAction === 'respond') {
        return await responseHandlers.submitResponse(ctx, req);
      }

      // GET /evaluations/:id/responses - List responses (HR only)
      if (method === 'GET' && evalAction === 'responses') {
        if (!canManageEvaluations(user.role)) {
          throw new Error('Forbidden: HR role required');
        }
        return await responseHandlers.listResponses(ctx);
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
