import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  CreateInterviewDTO,
  HandlerContext,
  InterviewerAssignmentRecord,
  InterviewRecord,
  InterviewResponse,
  InterviewRoundRecord,
  InterviewRoundResponse,
  UpdateInterviewDTO,
} from '../types.ts';
import { isValidUUID, jsonResponse } from '../utils.ts';

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
): InterviewRoundResponse {
  return {
    id: round.id,
    roundType: round.round_type,
    sequence: round.sequence,
    evaluationInstanceId: round.evaluation_instance_id,
    createdAt: round.created_at,
    assignments: assignments.map((a) => ({
      id: a.id,
      userId: a.user_id,
      createdAt: a.created_at,
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
    // Require evaluation_template_id on every round
    if (!round.evaluation_template_id || !isValidUUID(round.evaluation_template_id)) {
      throw new Error(`Round "${round.round_type}" must have a valid evaluation_template_id`);
    }
  }

  // Batch-validate evaluation templates — all must exist, be active, and belong to tenant
  const uniqueTemplateIds = [...new Set(body.rounds.map((r) => r.evaluation_template_id))];
  const { data: templates, error: templateError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .select('id')
    .in('id', uniqueTemplateIds)
    .eq('tenant_id', ctx.tenantId)
    .eq('is_active', true);

  if (templateError) {
    throw new Error(`Failed to validate evaluation templates: ${templateError.message}`);
  }

  const foundTemplateIds = new Set((templates || []).map((t: { id: string }) => t.id));
  for (const tid of uniqueTemplateIds) {
    if (!foundTemplateIds.has(tid)) {
      throw new Error(`Evaluation template not found or inactive: ${tid}`);
    }
  }

  // Validate templates are allowed for this pipeline stage via stage_evaluations
  const { data: stageEvals, error: stageEvalError } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .select('evaluation_template_id')
    .eq('tenant_id', ctx.tenantId)
    .eq('stage_id', body.pipeline_stage_id)
    .eq('is_active', true);

  if (stageEvalError) {
    throw new Error(`Failed to validate stage evaluations: ${stageEvalError.message}`);
  }

  const allowedTemplateIds = new Set(
    (stageEvals || []).map((se: { evaluation_template_id: string }) => se.evaluation_template_id),
  );

  for (const tid of uniqueTemplateIds) {
    if (!allowedTemplateIds.has(tid)) {
      throw new Error(
        `TEMPLATE_NOT_ALLOWED_FOR_STAGE: Template ${tid} is not configured for stage ${body.pipeline_stage_id}`,
      );
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

  // Insert rounds, assignments, and evaluation instances with rollback
  const roundResponses: InterviewRoundResponse[] = [];
  const createdEvalInstanceIds: string[] = [];

  try {
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

      // Retry safety: skip eval instance creation if already set
      if (!roundRecord.evaluation_instance_id) {
        // Find-or-create: ensure_stage_evaluations may have already created
        // a PENDING instance with the same unique key
        // (tenant_id, application_id, template_id, stage_id)
        let evalInstanceId: string;

        const { data: existingInstance } = await ctx.supabaseAdmin
          .from('evaluation_instances')
          .select('id, status')
          .eq('tenant_id', ctx.tenantId)
          .eq('application_id', applicationId)
          .eq('template_id', roundDTO.evaluation_template_id)
          .eq('stage_id', interviewRecord.pipeline_stage_id)
          .maybeSingle();

        if (existingInstance) {
          evalInstanceId = existingInstance.id;
        } else {
          // No existing instance — create one
          const { data: evalInstance, error: evalError } = await ctx.supabaseAdmin
            .from('evaluation_instances')
            .insert({
              tenant_id: ctx.tenantId,
              application_id: applicationId,
              template_id: roundDTO.evaluation_template_id,
              stage_id: interviewRecord.pipeline_stage_id,
              status: 'PENDING',
              created_by: ctx.userId,
            })
            .select()
            .single();

          if (evalError) {
            throw new Error(`Failed to create evaluation instance: ${evalError.message}`);
          }

          evalInstanceId = evalInstance.id;
          createdEvalInstanceIds.push(evalInstanceId);
        }

        // Idempotent participant insert — upsert ignores duplicates on
        // unique constraint (evaluation_id, user_id)
        const participantInserts = roundDTO.interviewer_ids.map((userId) => ({
          tenant_id: ctx.tenantId,
          evaluation_id: evalInstanceId,
          user_id: userId,
          status: 'PENDING',
        }));

        const { error: partError } = await ctx.supabaseAdmin
          .from('evaluation_participants')
          .upsert(participantInserts, {
            onConflict: 'evaluation_id,user_id',
            ignoreDuplicates: true,
          });

        if (partError) {
          throw new Error(`Failed to create evaluation participants: ${partError.message}`);
        }

        // Link round to evaluation instance (only if not already linked)
        const { error: linkError } = await ctx.supabaseAdmin
          .from('interview_rounds')
          .update({ evaluation_instance_id: evalInstanceId })
          .eq('id', roundRecord.id);

        if (linkError) {
          throw new Error(`Failed to link round to evaluation instance: ${linkError.message}`);
        }

        roundRecord.evaluation_instance_id = evalInstanceId;
      }

      roundResponses.push(
        formatRoundResponse(roundRecord, (assignments || []) as InterviewerAssignmentRecord[]),
      );
    }
  } catch (error) {
    // Rollback: delete eval instances we created (participants cascade via FK)
    if (createdEvalInstanceIds.length > 0) {
      await ctx.supabaseAdmin
        .from('evaluation_instances')
        .delete()
        .in('id', createdEvalInstanceIds);
    }
    // Delete interview (cascades rounds + assignments)
    await ctx.supabaseAdmin
      .from('interviews')
      .delete()
      .eq('id', interviewRecord.id);
    throw error;
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

  const formatted = (data || []).map((i: InterviewRecord) => formatInterviewResponse(i));

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

  // Assemble round responses
  const roundResponses = roundRecords.map((round) => {
    const roundAssignments = allAssignments.filter((a) => a.round_id === round.id);
    return formatRoundResponse(round, roundAssignments);
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
// Batch helper — chunks .in() queries to avoid Supabase limits
// ============================================

async function batchIn<T>(
  client: SupabaseClient,
  table: string,
  column: string,
  ids: string[],
  select: string,
  chunkSize = 50,
): Promise<T[]> {
  if (ids.length === 0) return [];
  const results: T[] = [];
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const { data, error } = await client
      .from(table)
      .select(select)
      .in(column, chunk);
    if (error) {
      throw new Error(`Failed to fetch ${table}: ${error.message}`);
    }
    if (data) results.push(...(data as T[]));
  }
  return results;
}

// ============================================
// GET /my-pending
// ============================================

export async function listMyPending(ctx: HandlerContext): Promise<Response> {
  // SECURITY: always scoped to authenticated user from JWT — never accept interviewerId as param
  if (!ctx.userId) {
    throw new Error('Unauthorized: User ID required');
  }

  // Step 1: Fetch this user's assignments with joined round data
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

  // Step 2: Collect evaluation_instance_ids from rounds (filter out nulls)
  const evalInstanceIds = assignments
    .map((a: { round: InterviewRoundRecord }) => a.round.evaluation_instance_id)
    .filter((id: string | null): id is string => id !== null);

  if (evalInstanceIds.length === 0) {
    return jsonResponse({ data: [] });
  }

  // Step 3: Fetch my PENDING evaluation_participants (need user_id + status filters beyond batchIn)
  const pendingEvalParticipants = await (async () => {
    if (evalInstanceIds.length === 0) return [];
    const results: { evaluation_id: string }[] = [];
    const chunkSize = 50;
    for (let i = 0; i < evalInstanceIds.length; i += chunkSize) {
      const chunk = evalInstanceIds.slice(i, i + chunkSize);
      const { data, error } = await ctx.supabaseAdmin
        .from('evaluation_participants')
        .select('evaluation_id')
        .in('evaluation_id', chunk)
        .eq('user_id', ctx.userId)
        .eq('status', 'PENDING');
      if (error) {
        throw new Error(`Failed to fetch evaluation participants: ${error.message}`);
      }
      if (data) results.push(...data);
    }
    return results;
  })();

  const pendingEvalIds = new Set(
    pendingEvalParticipants.map((p) => p.evaluation_id),
  );

  // Step 4: Filter assignments to only those with pending evaluation participation
  const pendingAssignments = assignments.filter(
    (a: { round: InterviewRoundRecord }) =>
      a.round.evaluation_instance_id !== null &&
      pendingEvalIds.has(a.round.evaluation_instance_id!),
  );

  if (pendingAssignments.length === 0) {
    return jsonResponse({ data: [] });
  }

  // Get interview details for pending rounds (exclude cancelled)
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

  // Filter out assignments whose interviews are cancelled/missing
  const activePending = pendingAssignments.filter(
    (a: { round: InterviewRoundRecord }) => interviewMap.has(a.round.interview_id),
  );

  if (activePending.length === 0) {
    return jsonResponse({ data: [] });
  }

  // Step 5: Round completion — batch-fetch all assignments and evaluation participants
  const pendingRoundIds = [...new Set(activePending.map((a: { round_id: string }) => a.round_id))];
  const pendingRoundEvalIds = [
    ...new Set(
      activePending
        .map((a: { round: InterviewRoundRecord }) => a.round.evaluation_instance_id)
        .filter((id: string | null): id is string => id !== null),
    ),
  ];

  const allRoundAssignments = await batchIn<{ round_id: string; user_id: string }>(
    ctx.supabaseAdmin,
    'interviewer_assignments',
    'round_id',
    pendingRoundIds,
    'round_id, user_id',
  );

  // Fetch all evaluation participants for these eval instances to determine round completion
  const allEvalParticipants = await (async () => {
    if (pendingRoundEvalIds.length === 0) return [];
    const results: { evaluation_id: string; user_id: string; status: string }[] = [];
    const chunkSize = 50;
    for (let i = 0; i < pendingRoundEvalIds.length; i += chunkSize) {
      const chunk = pendingRoundEvalIds.slice(i, i + chunkSize);
      const { data, error } = await ctx.supabaseAdmin
        .from('evaluation_participants')
        .select('evaluation_id, user_id, status')
        .in('evaluation_id', chunk);
      if (error) {
        throw new Error(`Failed to fetch evaluation participants: ${error.message}`);
      }
      if (data) results.push(...data);
    }
    return results;
  })();

  // Build maps ONCE — O(n) over all assignments/participants
  const assignedUsersPerRound = new Map<string, Set<string>>();
  for (const a of allRoundAssignments) {
    if (!assignedUsersPerRound.has(a.round_id)) assignedUsersPerRound.set(a.round_id, new Set());
    assignedUsersPerRound.get(a.round_id)!.add(a.user_id);
  }

  // Build submitted users per eval instance from evaluation_participants with status = 'SUBMITTED'
  const submittedUsersPerEval = new Map<string, Set<string>>();
  for (const p of allEvalParticipants) {
    if (p.status === 'SUBMITTED') {
      if (!submittedUsersPerEval.has(p.evaluation_id)) submittedUsersPerEval.set(p.evaluation_id, new Set());
      submittedUsersPerEval.get(p.evaluation_id)!.add(p.user_id);
    }
  }

  // Step 6: Display enrichment — batch-fetch applications, jobs, pipeline_stages
  const applicationIds = [
    ...new Set(
      (interviews || []).map((i: InterviewRecord) => i.application_id),
    ),
  ];
  const stageIds = [
    ...new Set(
      (interviews || []).map((i: InterviewRecord) => i.pipeline_stage_id),
    ),
  ];

  const [appRows, stageRows] = await Promise.all([
    batchIn<{ id: string; applicant_name: string; job_id: string }>(
      ctx.supabaseAdmin,
      'applications',
      'id',
      applicationIds,
      'id, applicant_name, job_id',
    ),
    batchIn<{ id: string; stage_name: string }>(
      ctx.supabaseAdmin,
      'pipeline_stages',
      'id',
      stageIds,
      'id, stage_name',
    ),
  ]);

  const appMap = new Map(appRows.map((a) => [a.id, { applicantName: a.applicant_name, jobId: a.job_id }]));
  const stageMap = new Map(stageRows.map((s) => [s.id, s.stage_name]));

  // Collect job IDs from resolved applications, then batch-fetch jobs
  const jobIds = [
    ...new Set(
      appRows.map((a) => a.job_id).filter(Boolean),
    ),
  ];

  const jobRows = await batchIn<{ id: string; title: string }>(
    ctx.supabaseAdmin,
    'jobs',
    'id',
    jobIds,
    'id, title',
  );
  const jobMap = new Map(jobRows.map((j) => [j.id, j.title]));

  // Step 7: Logged fallbacks — aggregate misses, log once per request
  const missingApps: string[] = [];
  const missingJobs: string[] = [];
  const missingStages: string[] = [];

  const result = activePending.map(
    (a: { round: InterviewRoundRecord; round_id: string; created_at: string }) => {
      const interview = interviewMap.get(a.round.interview_id) as InterviewRecord;

      const app = appMap.get(interview.application_id);
      if (!app) missingApps.push(interview.application_id);

      const jobTitle = app ? (jobMap.get(app.jobId) ?? null) : null;
      if (app && !jobTitle) missingJobs.push(app.jobId);

      if (!stageMap.has(interview.pipeline_stage_id)) missingStages.push(interview.pipeline_stage_id);

      // Round completion: compare assigned users to submitted evaluation participants
      const assignedSet = assignedUsersPerRound.get(a.round_id) ?? new Set();
      const evalId = a.round.evaluation_instance_id!;
      const submittedSet = submittedUsersPerEval.get(evalId) ?? new Set();
      const roundComplete = submittedSet.size >= assignedSet.size;

      return {
        roundId: a.round.id,
        interviewId: interview.id,
        applicationId: interview.application_id,
        applicantName: app?.applicantName ?? 'Unknown',
        jobTitle: jobTitle ?? 'Unknown',
        // stage.id MUST come from interview record, not lookup — stage record may be deleted
        stage: {
          id: interview.pipeline_stage_id,
          name: stageMap.get(interview.pipeline_stage_id) ?? 'Unknown',
        },
        roundType: a.round.round_type,
        roundComplete,
        evaluationInstanceId: evalId,
        interviewStatus: interview.status,
        assignedAt: a.created_at,
      };
    },
  );

  if (missingApps.length > 0) {
    console.error('Missing applications during /my-pending enrichment', {
      count: missingApps.length,
      sample: missingApps.slice(0, 3),
    });
  }
  if (missingJobs.length > 0) {
    console.error('Missing jobs during /my-pending enrichment', {
      count: missingJobs.length,
      sample: missingJobs.slice(0, 3),
    });
  }
  if (missingStages.length > 0) {
    console.error('Missing pipeline stages during /my-pending enrichment', {
      count: missingStages.length,
      sample: missingStages.slice(0, 3),
    });
  }

  return jsonResponse({ data: result });
}
