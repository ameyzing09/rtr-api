import type {
  AddParticipantDTO,
  EvaluationInstanceRecord,
  EvaluationParticipantRecord,
  EvaluationParticipantResponse,
  HandlerContext,
} from '../types.ts';
import { isValidUUID, jsonResponse } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatParticipantResponse(
  record: EvaluationParticipantRecord,
  userName?: string,
  userEmail?: string,
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
  const evaluationId = ctx.pathParts[0];

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

  // Step 1: fetch participants (no embedded join — auth.users isn't PostgREST-accessible)
  type ParticipantRow = {
    id: string;
    tenant_id: string;
    evaluation_id: string;
    user_id: string;
    status: string;
    submitted_at: string | null;
    created_at: string;
  };

  const { data: participants, error } = await ctx.supabaseAdmin
    .from('evaluation_participants')
    .select('id, tenant_id, evaluation_id, user_id, status, submitted_at, created_at')
    .eq('tenant_id', ctx.tenantId)
    .eq('evaluation_id', evaluationId)
    .order('created_at', { ascending: true });

  if (error) {
    throw new Error(`Failed to fetch participants: ${error.message}`);
  }

  const rows = (participants ?? []) as ParticipantRow[];

  // Step 2: batch-fetch profile names
  type ProfileRow = { id: string; name: string | null };

  const userIds = Array.from(new Set(rows.map((p) => p.user_id)));
  const nameById = new Map<string, string>();

  if (userIds.length > 0) {
    const { data: profiles, error: pErr } = await ctx.supabaseAdmin
      .from('user_profiles')
      .select('id, name')
      .eq('tenant_id', ctx.tenantId)
      .in('id', userIds);

    if (pErr) {
      throw new Error(`Failed to fetch user profiles: ${pErr.message}`);
    }

    for (const pr of (profiles ?? []) as ProfileRow[]) {
      if (pr.name) nameById.set(pr.id, pr.name);
    }
  }

  // Step 3: format
  const formatted = rows.map((r) =>
    formatParticipantResponse(
      r as unknown as EvaluationParticipantRecord,
      nameById.get(r.user_id), // userName
      undefined, // userEmail — not available without auth.users access
    )
  );

  return jsonResponse({ data: formatted });
}

// POST /evaluations/:id/participants
export async function addParticipant(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const evaluationId = ctx.pathParts[0];

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
    201,
  );
}

// DELETE /evaluations/:id/participants/:participantId
export async function removeParticipant(ctx: HandlerContext): Promise<Response> {
  const evaluationId = ctx.pathParts[0];
  const participantId = ctx.pathParts[2];

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
