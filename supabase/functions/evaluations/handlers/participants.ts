import type {
  HandlerContext,
  EvaluationInstanceRecord,
  EvaluationParticipantRecord,
  EvaluationParticipantResponse,
  AddParticipantDTO,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatParticipantResponse(
  record: EvaluationParticipantRecord,
  userName?: string,
  userEmail?: string
): EvaluationParticipantResponse {
  return {
    id: record.id,
    evaluationId: record.evaluation_id,
    userId: record.user_id,
    userName,
    userEmail,
    status: record.status,
    submittedAt: record.submitted_at,
    createdAt: record.created_at,
  };
}

// ============================================================================
// PARTICIPANT HANDLERS
// ============================================================================

// GET /evaluations/:id/participants
export async function listParticipants(ctx: HandlerContext): Promise<Response> {
  const evaluationId = ctx.pathParts[1];

  if (!isValidUUID(evaluationId)) {
    throw new Error('Invalid evaluation ID format');
  }

  // Verify evaluation exists and user has access
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
    .from('evaluation_participants')
    .select(`
      *,
      auth_user:user_id (
        email,
        raw_user_meta_data
      )
    `)
    .eq('evaluation_id', evaluationId)
    .order('created_at');

  if (error) {
    throw new Error(`Failed to fetch participants: ${error.message}`);
  }

  const formatted = (data || []).map((p: Record<string, unknown>) => {
    const authUser = p.auth_user as { email: string; raw_user_meta_data?: { full_name?: string } } | null;
    return formatParticipantResponse(
      p as unknown as EvaluationParticipantRecord,
      authUser?.raw_user_meta_data?.full_name,
      authUser?.email
    );
  });

  return jsonResponse({ data: formatted });
}

// POST /evaluations/:id/participants
export async function addParticipant(
  ctx: HandlerContext,
  req: Request
): Promise<Response> {
  const evaluationId = ctx.pathParts[1];

  if (!isValidUUID(evaluationId)) {
    throw new Error('Invalid evaluation ID format');
  }

  const body: AddParticipantDTO = await req.json();

  if (!body.user_id || !isValidUUID(body.user_id)) {
    throw new Error('user_id is required');
  }

  // Verify evaluation exists and is not completed/cancelled
  const { data: evaluation, error: evalError } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select('*')
    .eq('id', evaluationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (evalError || !evaluation) {
    throw new Error('Evaluation not found');
  }

  const instance = evaluation as EvaluationInstanceRecord;

  if (instance.status === 'COMPLETED' || instance.status === 'CANCELLED') {
    throw new Error(`Cannot add participants to ${instance.status.toLowerCase()} evaluation`);
  }

  // Add participant
  const { data, error } = await ctx.supabaseAdmin
    .from('evaluation_participants')
    .insert({
      tenant_id: ctx.tenantId,
      evaluation_id: evaluationId,
      user_id: body.user_id,
    })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new Error('User is already a participant in this evaluation');
    }
    throw new Error(`Failed to add participant: ${error.message}`);
  }

  return jsonResponse(
    { data: formatParticipantResponse(data as EvaluationParticipantRecord) },
    201
  );
}

// DELETE /evaluations/:id/participants/:participantId
export async function removeParticipant(ctx: HandlerContext): Promise<Response> {
  const evaluationId = ctx.pathParts[1];
  const participantId = ctx.pathParts[3];

  if (!isValidUUID(evaluationId) || !isValidUUID(participantId)) {
    throw new Error('Invalid ID format');
  }

  // Verify participant exists
  const { data: participant, error: fetchError } = await ctx.supabaseAdmin
    .from('evaluation_participants')
    .select('*')
    .eq('id', participantId)
    .eq('evaluation_id', evaluationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !participant) {
    throw new Error('Participant not found');
  }

  const pRecord = participant as EvaluationParticipantRecord;

  if (pRecord.status === 'SUBMITTED') {
    throw new Error('Cannot remove a participant who has already submitted');
  }

  const { error: deleteError } = await ctx.supabaseAdmin
    .from('evaluation_participants')
    .delete()
    .eq('id', participantId);

  if (deleteError) {
    throw new Error(`Failed to remove participant: ${deleteError.message}`);
  }

  return jsonResponse({ message: 'Participant removed successfully' });
}
