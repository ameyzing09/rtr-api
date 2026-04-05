import type { SupabaseClient } from '@supabase/supabase-js';
import type { EvaluationSummary } from '../types.ts';

// Fetch evaluation summaries for an application
// For restricted users (INTERVIEWER), only returns instances where user is a participant
export async function fetchEvaluationSummaries(
  supabaseAdmin: SupabaseClient,
  applicationId: string,
  tenantId: string,
  isRestricted: boolean,
  userId: string,
): Promise<EvaluationSummary[]> {
  // Step 1: Fetch evaluation instances with template + stage joins
  // Include BOTH stage-level (interview_round_id IS NULL) AND interview-level instances
  const { data, error } = await supabaseAdmin
    .from('evaluation_instances')
    .select(`
      id, tenant_id, application_id, template_id, stage_id,
      interview_round_id, status, completed_at, created_at,
      evaluation_templates!inner ( name ),
      pipeline_stages ( stage_name )
    `)
    .eq('tenant_id', tenantId)
    .eq('application_id', applicationId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(`Failed to fetch evaluations: ${error.message}`);
  }

  if (!data || data.length === 0) return [];

  const instanceIds = data.map((d: Record<string, unknown>) => d.id as string);

  // Step 2: Fetch all participants for these instances (tenant-scoped)
  const { data: participants } = await supabaseAdmin
    .from('evaluation_participants')
    .select('evaluation_id, user_id, status')
    .eq('tenant_id', tenantId)
    .in('evaluation_id', instanceIds);

  // Group participants by evaluation
  const participantsByEval: Record<string, { total: number; submitted: number; userIsParticipant: boolean }> = {};
  for (const p of (participants || [])) {
    const pRecord = p as { evaluation_id: string; user_id: string; status: string };
    if (!participantsByEval[pRecord.evaluation_id]) {
      participantsByEval[pRecord.evaluation_id] = { total: 0, submitted: 0, userIsParticipant: false };
    }
    participantsByEval[pRecord.evaluation_id].total++;
    if (pRecord.status === 'SUBMITTED') {
      participantsByEval[pRecord.evaluation_id].submitted++;
    }
    if (pRecord.user_id === userId) {
      participantsByEval[pRecord.evaluation_id].userIsParticipant = true;
    }
  }

  // Step 3: Format and filter
  const summaries: EvaluationSummary[] = [];
  for (const d of data) {
    const record = d as Record<string, unknown>;
    const evalId = record.id as string;
    const counts = participantsByEval[evalId] || { total: 0, submitted: 0, userIsParticipant: false };

    // For restricted users, only include instances where user is a participant
    if (isRestricted && !counts.userIsParticipant) {
      continue;
    }

    const template = record.evaluation_templates as { name: string } | null;
    const stage = record.pipeline_stages as { stage_name: string } | null;

    summaries.push({
      id: evalId,
      applicationId: record.application_id as string,
      templateId: record.template_id as string,
      templateName: template?.name ?? null,
      stageId: (record.stage_id as string) ?? null,
      stageName: stage?.stage_name ?? null,
      status: record.status as string,
      participantCount: counts.total,
      submittedCount: counts.submitted,
      pendingCount: counts.total - counts.submitted,
      isInterviewLevel: record.interview_round_id !== null,
      createdAt: record.created_at as string,
    });
  }

  return summaries;
}
