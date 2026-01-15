import type {
  HandlerContext,
  ApplicationStageHistoryRecord,
  PipelineStageRecord,
  StageHistoryResponse,
} from '../types.ts';
import { jsonResponse, formatHistoryResponse, isValidUUID } from '../utils.ts';

// GET /applications/:id/history - Get stage transition history
export async function getHistory(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Get query params for pagination
  const params = Object.fromEntries(ctx.url.searchParams);
  const limit = Math.min(parseInt(params.limit || '50', 10), 100);
  const offset = parseInt(params.offset || '0', 10);

  // Verify application exists and belongs to tenant
  const { data: state, error: stateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .select('id, pipeline_id')
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (stateError || !state) {
    throw new Error(`Tracking state for application ${applicationId} not found`);
  }

  // Get history entries
  const { data: history, error: historyError, count } = await ctx.supabaseUser
    .from('application_stage_history')
    .select('*', { count: 'exact' })
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .order('changed_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (historyError) {
    throw new Error(`Failed to fetch history: ${historyError.message}`);
  }

  // Get all stage IDs from history to batch fetch stage names
  const stageIds = new Set<string>();
  for (const entry of (history || [])) {
    if (entry.from_stage_id) stageIds.add(entry.from_stage_id);
    if (entry.to_stage_id) stageIds.add(entry.to_stage_id);
  }

  // Fetch all stages in one query
  const stagesMap = new Map<string, PipelineStageRecord>();
  if (stageIds.size > 0) {
    const { data: stages } = await ctx.supabaseAdmin
      .from('pipeline_stages')
      .select('*')
      .in('id', Array.from(stageIds));

    for (const stage of (stages || [])) {
      stagesMap.set(stage.id, stage as PipelineStageRecord);
    }
  }

  // Format response
  const formattedHistory: StageHistoryResponse[] = (history || []).map((entry) => {
    const fromStage = entry.from_stage_id ? stagesMap.get(entry.from_stage_id) || null : null;
    const toStage = entry.to_stage_id ? stagesMap.get(entry.to_stage_id) || null : null;
    return formatHistoryResponse(entry as ApplicationStageHistoryRecord, fromStage, toStage);
  });

  return jsonResponse({
    data: formattedHistory,
    pagination: {
      total: count || 0,
      limit,
      offset,
      hasMore: (offset + limit) < (count || 0),
    },
  });
}
