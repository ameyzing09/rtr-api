import type {
  HandlerContext,
  InterviewRecord,
  InterviewRoundRecord,
  InterviewerAssignmentRecord,
  InterviewFeedbackRecord,
  InterviewResponse,
  InterviewRoundResponse,
  CreateInterviewDTO,
  UpdateInterviewDTO,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================
// Formatters
// ============================================

function formatInterviewResponse(record: InterviewRecord): InterviewResponse {
  return {
    id: record.id,
    applicationId: record.application_id,
    pipelineStageId: record.pipeline_stage_id,
    status: record.status,
    createdBy: record.created_by,
    createdAt: record.created_at,
    updatedAt: record.updated_at,
  };
}

function formatRoundResponse(
  round: InterviewRoundRecord,
  assignments: InterviewerAssignmentRecord[],
  feedback: InterviewFeedbackRecord[],
): InterviewRoundResponse {
  return {
    id: round.id,
    roundType: round.round_type,
    sequence: round.sequence,
    createdAt: round.created_at,
    assignments: assignments.map((a) => ({
      id: a.id,
      userId: a.user_id,
      createdAt: a.created_at,
    })),
    feedback: feedback.map((f) => ({
      id: f.id,
      submittedBy: f.submitted_by,
      decision: f.decision,
      notes: f.notes,
      createdAt: f.created_at,
    })),
  };
}

// ============================================
// POST /applications/:id/interviews
// ============================================

export async function createInterview(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const applicationId = ctx.pathParts[1];
  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application_id format');
  }

  const body: CreateInterviewDTO = await req.json();

  // Validate required fields
  if (!body.pipeline_stage_id || !isValidUUID(body.pipeline_stage_id)) {
    throw new Error('pipeline_stage_id is required and must be a valid UUID');
  }
  if (!body.rounds || !Array.isArray(body.rounds) || body.rounds.length === 0) {
    throw new Error('rounds is required and must be a non-empty array');
  }

  // Validate each round
  const sequences = new Set<number>();
  for (const round of body.rounds) {
    if (!round.round_type || round.round_type.trim() === '') {
      throw new Error('Each round must have a round_type');
    }
    if (typeof round.sequence !== 'number' || round.sequence < 1) {
      throw new Error('Each round must have a positive integer sequence');
    }
    if (sequences.has(round.sequence)) {
      throw new Error(`Duplicate sequence number: ${round.sequence}`);
    }
    sequences.add(round.sequence);
    if (!round.interviewer_ids || !Array.isArray(round.interviewer_ids) || round.interviewer_ids.length === 0) {
      throw new Error(`Round "${round.round_type}" must have at least one interviewer`);
    }
    for (const uid of round.interviewer_ids) {
      if (!isValidUUID(uid)) {
        throw new Error(`Invalid interviewer UUID: ${uid}`);
      }
    }
  }

  // Verify application exists
  const { data: app, error: appError } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .single();

  if (appError || !app) {
    throw new Error('Application not found');
  }

  // Insert interview
  const { data: interview, error: interviewError } = await ctx.supabaseAdmin
    .from('interviews')
    .insert({
      tenant_id: ctx.tenantId,
      application_id: applicationId,
      pipeline_stage_id: body.pipeline_stage_id,
      status: 'PLANNED',
      created_by: ctx.userId,
    })
    .select()
    .single();

  if (interviewError) {
    throw new Error(`Failed to create interview: ${interviewError.message}`);
  }

  const interviewRecord = interview as InterviewRecord;

  // Insert rounds and assignments
  const roundResponses: InterviewRoundResponse[] = [];

  for (const roundDTO of body.rounds) {
    const { data: round, error: roundError } = await ctx.supabaseAdmin
      .from('interview_rounds')
      .insert({
        tenant_id: ctx.tenantId,
        interview_id: interviewRecord.id,
        round_type: roundDTO.round_type.trim(),
        sequence: roundDTO.sequence,
      })
      .select()
      .single();

    if (roundError) {
      throw new Error(`Failed to create round: ${roundError.message}`);
    }

    const roundRecord = round as InterviewRoundRecord;

    // Insert assignments for this round
    const assignmentInserts = roundDTO.interviewer_ids.map((userId) => ({
      tenant_id: ctx.tenantId,
      round_id: roundRecord.id,
      user_id: userId,
    }));

    const { data: assignments, error: assignError } = await ctx.supabaseAdmin
      .from('interviewer_assignments')
      .insert(assignmentInserts)
      .select();

    if (assignError) {
      if (assignError.code === '23505') {
        throw new Error('Duplicate interviewer assignment in round');
      }
      throw new Error(`Failed to create assignments: ${assignError.message}`);
    }

    roundResponses.push(
      formatRoundResponse(roundRecord, (assignments || []) as InterviewerAssignmentRecord[], []),
    );
  }

  const response = formatInterviewResponse(interviewRecord);
  response.rounds = roundResponses;

  return jsonResponse({ data: response }, 201);
}

// ============================================
// GET /applications/:id/interviews
// ============================================

export async function listInterviews(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];
  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application_id format');
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('interviews')
    .select('*')
    .eq('tenant_id', ctx.tenantId)
    .eq('application_id', applicationId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(`Failed to fetch interviews: ${error.message}`);
  }

  const formatted = (data || []).map((i: InterviewRecord) =>
    formatInterviewResponse(i),
  );

  return jsonResponse({ data: formatted });
}

// ============================================
// GET /interviews/:id
// ============================================

export async function getInterview(ctx: HandlerContext): Promise<Response> {
  const interviewId = ctx.pathParts[1];
  if (!isValidUUID(interviewId)) {
    throw new Error('Invalid interview_id format');
  }

  // Fetch interview
  const { data: interview, error: intError } = await ctx.supabaseAdmin
    .from('interviews')
    .select('*')
    .eq('id', interviewId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (intError || !interview) {
    throw new Error('Interview not found');
  }

  const interviewRecord = interview as InterviewRecord;

  // Fetch rounds
  const { data: rounds } = await ctx.supabaseAdmin
    .from('interview_rounds')
    .select('*')
    .eq('interview_id', interviewId)
    .order('sequence');

  const roundRecords = (rounds || []) as InterviewRoundRecord[];
  const roundIds = roundRecords.map((r) => r.id);

  // Fetch assignments for all rounds
  const { data: assignments } = await ctx.supabaseAdmin
    .from('interviewer_assignments')
    .select('*')
    .in('round_id', roundIds.length > 0 ? roundIds : ['00000000-0000-0000-0000-000000000000']);

  const allAssignments = (assignments || []) as InterviewerAssignmentRecord[];

  // Fetch feedback for all rounds
  const { data: feedback } = await ctx.supabaseAdmin
    .from('interview_feedback')
    .select('*')
    .in('round_id', roundIds.length > 0 ? roundIds : ['00000000-0000-0000-0000-000000000000']);

  let allFeedback = (feedback || []) as InterviewFeedbackRecord[];

  // Feedback visibility rules:
  // HR+ (SUPERADMIN, ADMIN, HR): full visibility — all feedback
  // INTERVIEWER: restricted — only their own feedback
  const isHRPlus = ['SUPERADMIN', 'ADMIN', 'HR'].includes(ctx.userRole || '');
  if (!isHRPlus && ctx.userId) {
    allFeedback = allFeedback.filter((f) => f.submitted_by === ctx.userId);
  }

  // Assemble round responses
  const roundResponses = roundRecords.map((round) => {
    const roundAssignments = allAssignments.filter((a) => a.round_id === round.id);
    const roundFeedback = allFeedback.filter((f) => f.round_id === round.id);
    return formatRoundResponse(round, roundAssignments, roundFeedback);
  });

  const response = formatInterviewResponse(interviewRecord);
  response.rounds = roundResponses;

  return jsonResponse({ data: response });
}

// ============================================
// PATCH /interviews/:id
// ============================================

export async function updateInterview(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const interviewId = ctx.pathParts[1];
  if (!isValidUUID(interviewId)) {
    throw new Error('Invalid interview_id format');
  }

  const body: UpdateInterviewDTO = await req.json();

  if (body.status !== 'CANCELLED') {
    throw new Error('Only CANCELLED status is supported for updates');
  }

  // Fetch current interview
  const { data: existing, error: fetchError } = await ctx.supabaseAdmin
    .from('interviews')
    .select('*')
    .eq('id', interviewId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !existing) {
    throw new Error('Interview not found');
  }

  if (existing.status === 'CANCELLED') {
    throw new Error('Interview is already cancelled');
  }

  const { data: updated, error: updateError } = await ctx.supabaseAdmin
    .from('interviews')
    .update({ status: 'CANCELLED' })
    .eq('id', interviewId)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (updateError) {
    throw new Error(`Failed to update interview: ${updateError.message}`);
  }

  return jsonResponse({ data: formatInterviewResponse(updated as InterviewRecord) });
}

// ============================================
// GET /my-pending
// ============================================

export async function listMyPending(ctx: HandlerContext): Promise<Response> {
  if (!ctx.userId) {
    throw new Error('Unauthorized: User ID required');
  }

  // Find assignments for current user where no feedback exists yet
  const { data: assignments, error: assignError } = await ctx.supabaseAdmin
    .from('interviewer_assignments')
    .select('*, round:interview_rounds!inner(*)')
    .eq('tenant_id', ctx.tenantId)
    .eq('user_id', ctx.userId);

  if (assignError) {
    throw new Error(`Failed to fetch assignments: ${assignError.message}`);
  }

  if (!assignments || assignments.length === 0) {
    return jsonResponse({ data: [] });
  }

  // Get all round IDs to check for existing feedback
  const roundIds = assignments.map((a: { round_id: string }) => a.round_id);

  const { data: existingFeedback } = await ctx.supabaseAdmin
    .from('interview_feedback')
    .select('round_id')
    .eq('submitted_by', ctx.userId)
    .in('round_id', roundIds);

  const feedbackRoundIds = new Set(
    (existingFeedback || []).map((f: { round_id: string }) => f.round_id),
  );

  // Filter to only rounds without feedback
  const pendingAssignments = assignments.filter(
    (a: { round_id: string }) => !feedbackRoundIds.has(a.round_id),
  );

  if (pendingAssignments.length === 0) {
    return jsonResponse({ data: [] });
  }

  // Get interview details for pending rounds
  const interviewIds = [
    ...new Set(
      pendingAssignments.map(
        (a: { round: InterviewRoundRecord }) => a.round.interview_id,
      ),
    ),
  ];

  const { data: interviews } = await ctx.supabaseAdmin
    .from('interviews')
    .select('*')
    .in('id', interviewIds)
    .neq('status', 'CANCELLED');

  const interviewMap = new Map(
    (interviews || []).map((i: InterviewRecord) => [i.id, i]),
  );

  const result = pendingAssignments
    .filter((a: { round: InterviewRoundRecord }) =>
      interviewMap.has(a.round.interview_id),
    )
    .map((a: { round: InterviewRoundRecord; created_at: string }) => {
      const interview = interviewMap.get(a.round.interview_id) as InterviewRecord;
      return {
        roundId: a.round.id,
        roundType: a.round.round_type,
        sequence: a.round.sequence,
        interviewId: interview.id,
        applicationId: interview.application_id,
        pipelineStageId: interview.pipeline_stage_id,
        interviewStatus: interview.status,
        assignedAt: a.created_at,
      };
    });

  return jsonResponse({ data: result });
}
