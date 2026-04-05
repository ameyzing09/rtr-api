import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  InterviewerAssignmentRecord,
  InterviewRecord,
  InterviewRoundRecord,
  InterviewSummary,
  PipelineStageRecord,
  UserProfileRecord,
} from '../types.ts';
import { batchIn } from './_shared.ts';

// Fetch interview summaries for an application
export async function fetchInterviewSummaries(
  supabaseAdmin: SupabaseClient,
  applicationId: string,
  tenantId: string,
): Promise<InterviewSummary[]> {
  // Step 1: Fetch interviews for this application
  const { data: interviews, error: interviewError } = await supabaseAdmin
    .from('interviews')
    .select('id, tenant_id, application_id, pipeline_stage_id, status, created_by, created_at, updated_at')
    .eq('application_id', applicationId)
    .eq('tenant_id', tenantId)
    .order('created_at', { ascending: false });

  if (interviewError) {
    throw new Error(`Failed to fetch interviews: ${interviewError.message}`);
  }

  if (!interviews || interviews.length === 0) return [];

  const interviewRecords = interviews as InterviewRecord[];
  const interviewIds = interviewRecords.map((i) => i.id);

  // Step 2: Fetch rounds for those interviews
  const rounds = await batchIn<InterviewRoundRecord>(
    supabaseAdmin,
    'interview_rounds',
    'interview_id',
    interviewIds,
    'id, tenant_id, interview_id, round_type, sequence, evaluation_instance_id',
  );

  // Group rounds by interview ID
  const roundsByInterview = new Map<string, InterviewRoundRecord[]>();
  for (const round of rounds) {
    if (!roundsByInterview.has(round.interview_id)) {
      roundsByInterview.set(round.interview_id, []);
    }
    roundsByInterview.get(round.interview_id)!.push(round);
  }

  const roundIds = rounds.map((r) => r.id);

  // Step 3: Fetch assignments for those rounds
  const assignments = await batchIn<InterviewerAssignmentRecord>(
    supabaseAdmin,
    'interviewer_assignments',
    'round_id',
    roundIds,
    'id, tenant_id, round_id, user_id',
  );

  // Group assignments by round ID
  const assignmentsByRound = new Map<string, InterviewerAssignmentRecord[]>();
  for (const a of assignments) {
    if (!assignmentsByRound.has(a.round_id)) {
      assignmentsByRound.set(a.round_id, []);
    }
    assignmentsByRound.get(a.round_id)!.push(a);
  }

  // Collect unique user IDs and stage IDs for batch fetch
  const userIds = new Set<string>();
  for (const a of assignments) {
    userIds.add(a.user_id);
  }

  const stageIds = new Set<string>();
  for (const i of interviewRecords) {
    if (i.pipeline_stage_id) stageIds.add(i.pipeline_stage_id);
  }

  // Step 4: Batch fetch user profiles and stage names
  const [userProfiles, stages] = await Promise.all([
    userIds.size > 0
      ? batchIn<UserProfileRecord>(
          supabaseAdmin,
          'user_profiles',
          'id',
          Array.from(userIds),
          'id, name',
        )
      : Promise.resolve([]),
    stageIds.size > 0
      ? batchIn<PipelineStageRecord>(
          supabaseAdmin,
          'pipeline_stages',
          'id',
          Array.from(stageIds),
          'id, pipeline_id, stage_name, stage_type, order_index',
        )
      : Promise.resolve([]),
  ]);

  const usersMap = new Map<string, UserProfileRecord>();
  for (const u of userProfiles) {
    usersMap.set(u.id, u);
  }

  const stagesMap = new Map<string, PipelineStageRecord>();
  for (const s of stages) {
    stagesMap.set(s.id, s);
  }

  // Step 5: Fetch evaluation participants to determine completed rounds
  const evalInstanceIds = rounds
    .map((r) => r.evaluation_instance_id)
    .filter((id): id is string => id !== null);

  const evalParticipants = evalInstanceIds.length > 0
    ? await batchIn<{ evaluation_id: string; status: string }>(
        supabaseAdmin,
        'evaluation_participants',
        'evaluation_id',
        evalInstanceIds,
        'evaluation_id, status',
      )
    : [];

  // Map: evaluation_id -> { total, submitted }
  const evalCounts = new Map<string, { total: number; submitted: number }>();
  for (const p of evalParticipants) {
    if (!evalCounts.has(p.evaluation_id)) {
      evalCounts.set(p.evaluation_id, { total: 0, submitted: 0 });
    }
    const counts = evalCounts.get(p.evaluation_id)!;
    counts.total++;
    if (p.status === 'SUBMITTED') counts.submitted++;
  }

  // Step 6: Compose summaries
  return interviewRecords.map((interview) => {
    const interviewRounds = roundsByInterview.get(interview.id) || [];
    const roundCount = interviewRounds.length;

    // Completed rounds = rounds where all assigned participants have submitted
    let completedRounds = 0;
    for (const round of interviewRounds) {
      if (round.evaluation_instance_id) {
        const counts = evalCounts.get(round.evaluation_instance_id);
        if (counts && counts.total > 0 && counts.submitted >= counts.total) {
          completedRounds++;
        }
      }
    }

    // Collect unique interviewers across all rounds of this interview
    const interviewerSet = new Map<string, { userId: string; userName: string | null }>();
    for (const round of interviewRounds) {
      const roundAssignments = assignmentsByRound.get(round.id) || [];
      for (const a of roundAssignments) {
        if (!interviewerSet.has(a.user_id)) {
          const profile = usersMap.get(a.user_id);
          interviewerSet.set(a.user_id, {
            userId: a.user_id,
            userName: profile?.name ?? null,
          });
        }
      }
    }

    const stage = stagesMap.get(interview.pipeline_stage_id);

    return {
      id: interview.id,
      applicationId: interview.application_id,
      pipelineStageId: interview.pipeline_stage_id,
      stageName: stage?.stage_name ?? null,
      status: interview.status,
      roundCount,
      completedRounds,
      interviewers: Array.from(interviewerSet.values()),
      createdAt: interview.created_at,
    };
  });
}
