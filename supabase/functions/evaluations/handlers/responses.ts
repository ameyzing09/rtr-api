import type {
  EvaluationResponseRecord,
  EvaluationResponseResponse,
  HandlerContext,
  SubmitResponseDTO,
} from '../types.ts';
import { isValidUUID, jsonResponse } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatResponseResponse(record: EvaluationResponseRecord): EvaluationResponseResponse {
  return {
    id: record.id,
    participantId: record.participant_id,
    responseData: record.response_data,
    submittedAt: record.submitted_at,
  };
}

// Handle RPC errors
function handleRpcError(error: { code?: string; message?: string }): never {
  const msg = error.message || 'Unknown error';

  if (msg.includes('NOT_FOUND')) {
    throw new Error('Not found: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('FORBIDDEN')) {
    throw new Error('Forbidden: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('INVALID_ACTION')) {
    throw new Error('Bad request: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('VALIDATION')) {
    throw new Error('Bad request: ' + msg.split(': ').slice(1).join(': '));
  }

  throw new Error(msg);
}

// ============================================================================
// RESPONSE HANDLERS
// ============================================================================

// POST /evaluations/:id/respond
export async function submitResponse(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const evaluationId = ctx.pathParts[0];

  if (!isValidUUID(evaluationId)) {
    throw new Error('Invalid evaluation ID format');
  }

  const body: SubmitResponseDTO = await req.json();

  if (!body.response_data || typeof body.response_data !== 'object') {
    throw new Error('response_data is required and must be an object');
  }

  // Call RPC to submit response
  const { data, error } = await ctx.supabaseAdmin
    .rpc('submit_evaluation_response', {
      p_evaluation_id: evaluationId,
      p_user_id: ctx.userId,
      p_response_data: body.response_data,
    });

  if (error) {
    handleRpcError(error);
  }

  return jsonResponse({ data: formatResponseResponse(data as EvaluationResponseRecord) }, 201);
}

// GET /evaluations/:id/responses (HR only)
export async function listResponses(ctx: HandlerContext): Promise<Response> {
  const evaluationId = ctx.pathParts[0];

  if (!isValidUUID(evaluationId)) {
    throw new Error('Invalid evaluation ID format');
  }

  // Verify evaluation exists and belongs to tenant
  const { data: evaluation } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select('id')
    .eq('id', evaluationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!evaluation) {
    throw new Error('Evaluation not found');
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('evaluation_responses')
    .select(`
      *,
      evaluation_participants!inner (
        user_id,
        evaluation_id
      )
    `)
    .eq('evaluation_participants.evaluation_id', evaluationId)
    .order('submitted_at');

  if (error) {
    throw new Error(`Failed to fetch responses: ${error.message}`);
  }

  const formatted = (data || []).map((r: Record<string, unknown>) =>
    formatResponseResponse(r as unknown as EvaluationResponseRecord)
  );

  return jsonResponse({ data: formatted });
}
