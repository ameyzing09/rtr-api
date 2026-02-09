import type {
  HandlerContext,
  InterviewRoundRecord,
  InterviewRecord,
  InterviewFeedbackRecord,
  SubmitFeedbackDTO,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================
// POST /rounds/:roundId/feedback
// ============================================

export async function submitFeedback(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const roundId = ctx.pathParts[1];
  if (!isValidUUID(roundId)) {
    throw new Error('Invalid round_id format');
  }

  if (!ctx.userId) {
    throw new Error('Unauthorized: User ID required');
  }

  const body: SubmitFeedbackDTO = await req.json();

  // Validate decision
  if (!body.decision || !['PASS', 'FAIL', 'NEUTRAL'].includes(body.decision)) {
    throw new Error('decision is required and must be PASS, FAIL, or NEUTRAL');
  }

  // Fetch round + parent interview in one query
  const { data: round, error: roundError } = await ctx.supabaseAdmin
    .from('interview_rounds')
    .select('*, interview:interviews!inner(*)')
    .eq('id', roundId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (roundError || !round) {
    throw new Error('Round not found');
  }

  const roundRecord = round as InterviewRoundRecord & { interview: InterviewRecord };
  const interview = roundRecord.interview;

  // Reject if interview is CANCELLED
  if (interview.status === 'CANCELLED') {
    throw new Error('INVALID_ACTION: Cannot submit feedback on a cancelled interview');
  }

  // Validate user is assigned to this round
  const { data: assignment, error: assignError } = await ctx.supabaseAdmin
    .from('interviewer_assignments')
    .select('id')
    .eq('round_id', roundId)
    .eq('user_id', ctx.userId)
    .single();

  if (assignError || !assignment) {
    throw new Error('Forbidden: You are not assigned to this interview round');
  }

  // Insert feedback
  const { data: feedback, error: feedbackError } = await ctx.supabaseAdmin
    .from('interview_feedback')
    .insert({
      tenant_id: ctx.tenantId,
      round_id: roundId,
      submitted_by: ctx.userId,
      decision: body.decision,
      notes: body.notes || null,
    })
    .select()
    .single();

  if (feedbackError) {
    if (feedbackError.code === '23505') {
      throw new Error('You have already submitted feedback for this round');
    }
    throw new Error(`Failed to submit feedback: ${feedbackError.message}`);
  }

  const feedbackRecord = feedback as InterviewFeedbackRecord;

  // If interview status is PLANNED, update to IN_PROGRESS
  if (interview.status === 'PLANNED') {
    await ctx.supabaseAdmin
      .from('interviews')
      .update({ status: 'IN_PROGRESS' })
      .eq('id', interview.id);
  }

  // Emit signal immediately via RPC (per-feedback, latest wins)
  const { error: signalError } = await ctx.supabaseAdmin
    .rpc('emit_interview_signal', {
      p_application_id: interview.application_id,
      p_tenant_id: ctx.tenantId,
      p_pipeline_stage_id: interview.pipeline_stage_id,
      p_decision: body.decision,
      p_source_id: feedbackRecord.id,
      p_user_id: ctx.userId,
    });

  if (signalError) {
    // Log but don't fail the feedback submission
    console.error('Failed to emit interview signal:', signalError.message);
  }

  // Check if all assigned interviewers for this round have submitted
  const { count: assignmentCount } = await ctx.supabaseAdmin
    .from('interviewer_assignments')
    .select('*', { count: 'exact', head: true })
    .eq('round_id', roundId);

  const { count: feedbackCount } = await ctx.supabaseAdmin
    .from('interview_feedback')
    .select('*', { count: 'exact', head: true })
    .eq('round_id', roundId);

  const roundComplete = (feedbackCount ?? 0) >= (assignmentCount ?? 1);

  return jsonResponse({
    data: {
      id: feedbackRecord.id,
      roundId: feedbackRecord.round_id,
      submittedBy: feedbackRecord.submitted_by,
      decision: feedbackRecord.decision,
      notes: feedbackRecord.notes,
      createdAt: feedbackRecord.created_at,
      roundComplete,
    },
  });
}
