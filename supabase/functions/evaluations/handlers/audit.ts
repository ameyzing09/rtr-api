import type {
  HandlerContext,
  ActionExecutionLogRecord,
  ActionExecutionLogResponse,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatExecutionLogResponse(
  record: ActionExecutionLogRecord,
  executedByEmail?: string,
  reviewedByEmail?: string,
  approvedByEmail?: string,
  fromStageName?: string | null,
  toStageName?: string | null,
  stageName?: string | null
): ActionExecutionLogResponse {
  return {
    id: record.id,
    applicationId: record.application_id,
    actionCode: record.action_code,
    stageId: record.stage_id,
    stageName,
    executedBy: record.executed_by,
    executedByEmail,
    executedAt: record.executed_at,
    signalSnapshot: record.signal_snapshot,
    conditionsEvaluated: record.conditions_evaluated,
    decisionNote: record.decision_note,
    overrideReason: record.override_reason,
    reviewedBy: record.reviewed_by,
    reviewedByEmail,
    approvedBy: record.approved_by,
    approvedByEmail,
    outcomeType: record.outcome_type,
    isTerminal: record.is_terminal,
    fromStageId: record.from_stage_id,
    fromStageName,
    toStageId: record.to_stage_id,
    toStageName,
  };
}

// ============================================================================
// AUDIT HANDLERS
// ============================================================================

// GET /applications/:id/decision-log
export async function getDecisionLog(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Parse query params
  const limit = Math.min(parseInt(ctx.url.searchParams.get('limit') || '50'), 100);
  const offset = parseInt(ctx.url.searchParams.get('offset') || '0');
  const outcomeType = ctx.url.searchParams.get('outcome_type');
  const actionCode = ctx.url.searchParams.get('action_code');

  // Verify application exists and belongs to tenant
  const { data: application } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!application) {
    throw new Error('Application not found');
  }

  // Build query
  let query = ctx.supabaseAdmin
    .from('action_execution_log')
    .select('*', { count: 'exact' })
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .order('executed_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (outcomeType) {
    query = query.eq('outcome_type', outcomeType.toUpperCase());
  }

  if (actionCode) {
    query = query.eq('action_code', actionCode.toUpperCase());
  }

  const { data, error, count } = await query;

  if (error) {
    throw new Error(`Failed to fetch decision log: ${error.message}`);
  }

  const records = (data || []) as ActionExecutionLogRecord[];

  // Batch fetch user emails and stage names
  const userIds = new Set<string>();
  const stageIds = new Set<string>();

  for (const record of records) {
    userIds.add(record.executed_by);
    if (record.reviewed_by) userIds.add(record.reviewed_by);
    if (record.approved_by) userIds.add(record.approved_by);
    if (record.stage_id) stageIds.add(record.stage_id);
    if (record.from_stage_id) stageIds.add(record.from_stage_id);
    if (record.to_stage_id) stageIds.add(record.to_stage_id);
  }

  // Fetch user emails
  const userEmailMap: Record<string, string> = {};
  if (userIds.size > 0) {
    const { data: users } = await ctx.supabaseAdmin
      .from('user_profiles')
      .select('id, email')
      .in('id', Array.from(userIds));

    for (const user of (users || [])) {
      const u = user as { id: string; email: string };
      userEmailMap[u.id] = u.email;
    }
  }

  // Fetch stage names
  const stageNameMap: Record<string, string> = {};
  if (stageIds.size > 0) {
    const { data: stages } = await ctx.supabaseAdmin
      .from('pipeline_stages')
      .select('id, stage_name')
      .in('id', Array.from(stageIds));

    for (const stage of (stages || [])) {
      const s = stage as { id: string; stage_name: string };
      stageNameMap[s.id] = s.stage_name;
    }
  }

  // Format responses
  const formatted = records.map((record) =>
    formatExecutionLogResponse(
      record,
      userEmailMap[record.executed_by],
      record.reviewed_by ? userEmailMap[record.reviewed_by] : undefined,
      record.approved_by ? userEmailMap[record.approved_by] : undefined,
      record.from_stage_id ? stageNameMap[record.from_stage_id] : null,
      record.to_stage_id ? stageNameMap[record.to_stage_id] : null,
      record.stage_id ? stageNameMap[record.stage_id] : null
    )
  );

  return jsonResponse({
    data: formatted,
    pagination: {
      total: count || 0,
      limit,
      offset,
      hasMore: (count || 0) > offset + limit,
    },
  });
}

// GET /applications/:id/decision-log/:logId
export async function getDecisionLogEntry(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];
  const logId = ctx.pathParts[3];

  if (!isValidUUID(applicationId) || !isValidUUID(logId)) {
    throw new Error('Invalid ID format');
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('action_execution_log')
    .select('*')
    .eq('id', logId)
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (error || !data) {
    throw new Error('Decision log entry not found');
  }

  const record = data as ActionExecutionLogRecord;

  // Fetch user emails
  const userIds = [record.executed_by];
  if (record.reviewed_by) userIds.push(record.reviewed_by);
  if (record.approved_by) userIds.push(record.approved_by);

  const { data: users } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('id, email')
    .in('id', userIds);

  const userEmailMap: Record<string, string> = {};
  for (const user of (users || [])) {
    const u = user as { id: string; email: string };
    userEmailMap[u.id] = u.email;
  }

  // Fetch stage names
  const stageIds = [record.stage_id, record.from_stage_id, record.to_stage_id].filter(Boolean) as string[];

  const stageNameMap: Record<string, string> = {};
  if (stageIds.length > 0) {
    const { data: stages } = await ctx.supabaseAdmin
      .from('pipeline_stages')
      .select('id, stage_name')
      .in('id', stageIds);

    for (const stage of (stages || [])) {
      const s = stage as { id: string; stage_name: string };
      stageNameMap[s.id] = s.stage_name;
    }
  }

  return jsonResponse({
    data: formatExecutionLogResponse(
      record,
      userEmailMap[record.executed_by],
      record.reviewed_by ? userEmailMap[record.reviewed_by] : undefined,
      record.approved_by ? userEmailMap[record.approved_by] : undefined,
      record.from_stage_id ? stageNameMap[record.from_stage_id] : null,
      record.to_stage_id ? stageNameMap[record.to_stage_id] : null,
      record.stage_id ? stageNameMap[record.stage_id] : null
    ),
  });
}

// GET /applications/:id/rejection-reason
// Convenience endpoint to quickly answer "Why was this candidate rejected?"
export async function getRejectionReason(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Verify application exists and belongs to tenant
  const { data: application } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!application) {
    throw new Error('Application not found');
  }

  // Find the terminal FAILURE action
  const { data, error } = await ctx.supabaseAdmin
    .from('action_execution_log')
    .select('*')
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .eq('outcome_type', 'FAILURE')
    .eq('is_terminal', true)
    .order('executed_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to fetch rejection reason: ${error.message}`);
  }

  if (!data) {
    return jsonResponse({
      data: null,
      message: 'No rejection found for this application',
    });
  }

  const record = data as ActionExecutionLogRecord;

  // Fetch user email
  const { data: user } = await ctx.supabaseAdmin
    .from('user_profiles')
    .select('id, email')
    .eq('id', record.executed_by)
    .single();

  const userEmail = (user as { email: string } | null)?.email;

  // Fetch stage name
  let stageName: string | null = null;
  if (record.stage_id) {
    const { data: stage } = await ctx.supabaseAdmin
      .from('pipeline_stages')
      .select('stage_name')
      .eq('id', record.stage_id)
      .single();
    stageName = (stage as { stage_name: string } | null)?.stage_name || null;
  }

  return jsonResponse({
    data: {
      rejectedAt: record.executed_at,
      rejectedBy: record.executed_by,
      rejectedByEmail: userEmail,
      rejectionStage: stageName,
      actionCode: record.action_code,
      decisionNote: record.decision_note,
      signalSnapshot: record.signal_snapshot,
      conditionsEvaluated: record.conditions_evaluated,
    },
  });
}
