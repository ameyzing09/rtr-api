import type { SupabaseClient } from '@supabase/supabase-js';
import type { TrackingResponse } from '../types.ts';

// Fetch tracking state for an application (single joined query)
export async function fetchTrackingState(
  supabaseAdmin: SupabaseClient,
  applicationId: string,
  tenantId: string,
): Promise<TrackingResponse | null> {
  const { data, error } = await supabaseAdmin
    .from('application_pipeline_state')
    .select(`
      pipeline_id, current_stage_id, status, outcome_type,
      is_terminal, entered_stage_at,
      pipeline_stages!inner ( stage_name, order_index )
    `)
    .eq('application_id', applicationId)
    .eq('tenant_id', tenantId)
    .single();

  if (error || !data) {
    // Application may not be attached to pipeline yet
    return null;
  }

  const record = data as Record<string, unknown>;
  const stage = record.pipeline_stages as { stage_name: string; order_index: number } | null;

  return {
    pipelineId: record.pipeline_id as string,
    currentStageId: record.current_stage_id as string,
    currentStageName: stage?.stage_name ?? 'Unknown',
    currentStageIndex: stage?.order_index ?? 0,
    status: record.status as string,
    outcomeType: record.outcome_type as string,
    isTerminal: record.is_terminal as boolean,
    enteredStageAt: record.entered_stage_at as string,
  };
}
