import type {
  ApplicationPipelineStateRecord,
  ApplicationStageHistoryRecord,
  PipelineStageRecord,
  TrackingStateResponse,
  StageHistoryResponse,
  PipelineStageResponse,
  ErrorResponse,
  TenantStatusRecord,
  TenantStatusResponse,
} from './types.ts';

// CORS headers
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-tenant-id, x-request-id',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
};

// CORS preflight response
export function corsResponse(): Response {
  return new Response(null, { status: 200, headers: corsHeaders });
}

// JSON response with CORS headers
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Text response for health check
export function textResponse(text: string, status = 200): Response {
  return new Response(text, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
  });
}

// Format tracking state for API response
export function formatTrackingStateResponse(
  state: ApplicationPipelineStateRecord,
  stage: PipelineStageRecord
): TrackingStateResponse {
  return {
    id: state.id,
    applicationId: state.application_id,
    jobId: state.job_id,
    pipelineId: state.pipeline_id,
    currentStageId: state.current_stage_id,
    currentStageName: stage.stage_name,
    currentStageIndex: stage.order_index,
    status: state.status,
    outcomeType: state.outcome_type,
    isTerminal: state.is_terminal,
    enteredStageAt: state.entered_stage_at,
    createdAt: state.created_at,
    updatedAt: state.updated_at,
  };
}

// Format stage history for API response
export function formatHistoryResponse(
  history: ApplicationStageHistoryRecord,
  fromStage: PipelineStageRecord | null,
  toStage: PipelineStageRecord | null
): StageHistoryResponse {
  return {
    id: history.id,
    applicationId: history.application_id,
    pipelineId: history.pipeline_id,
    fromStageId: history.from_stage_id,
    fromStageName: fromStage?.stage_name || null,
    toStageId: history.to_stage_id,
    toStageName: toStage?.stage_name || null,
    action: history.action,
    changedBy: history.changed_by,
    changedAt: history.changed_at,
    reason: history.reason,
  };
}

// Format pipeline stage for API response
export function formatStageResponse(stage: PipelineStageRecord): PipelineStageResponse {
  return {
    id: stage.id,
    stageName: stage.stage_name,
    stageType: stage.stage_type,
    conductedBy: stage.conducted_by,
    orderIndex: stage.order_index,
  };
}

// ============================================================================
// DEPRECATED: These functions used hardcoded statuses.
// Terminal/action lookups now happen in the RPC via tenant_application_statuses table.
// Keeping for backwards compatibility but should not be used for new code.
// ============================================================================

/**
 * @deprecated Use RPC which looks up is_terminal from tenant_application_statuses
 */
export function isTerminalStatus(_status: string): boolean {
  console.warn('isTerminalStatus is deprecated - terminal check now happens in RPC');
  return false;
}

/**
 * @deprecated Use RPC which looks up action_code from tenant_application_statuses
 */
export function getActionFromStatus(_status: string): string {
  console.warn('getActionFromStatus is deprecated - action lookup now happens in RPC');
  return 'MOVE';
}

// Format tenant status record to API response
export function formatStatusResponse(record: TenantStatusRecord): TenantStatusResponse {
  return {
    id: record.id,
    statusCode: record.status_code,
    displayName: record.display_name,
    actionCode: record.action_code,
    outcomeType: record.outcome_type,
    isTerminal: record.is_terminal,
    sortOrder: record.sort_order,
    colorHex: record.color_hex,
  };
}

// Validate UUID format
export function isValidUUID(str: string): boolean {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

// Error handler with spec-compliant format
export function handleError(error: unknown): Response {
  const err = error as Error;
  let status = 400;
  let code = 'validation_error';
  let details: string | undefined;

  const message = err.message || 'An error occurred';

  if (message.includes('not found') || message.includes('No rows')) {
    status = 404;
    code = 'not_found';
  } else if (message.includes('Unauthorized') || message.includes('Invalid or missing token')) {
    status = 401;
    code = 'unauthorized';
  } else if (message.includes('Forbidden') || message.includes('Missing permission') || message.includes('role required')) {
    status = 403;
    code = 'forbidden';
  } else if (message.includes('already attached') || message.includes('duplicate') || message.includes('conflict')) {
    status = 409;
    code = 'conflict';
  } else if (message.includes('terminal') || message.includes('cannot move')) {
    status = 403;
    code = 'forbidden';
    details = 'Application is in a terminal state';
  } else if (message.includes('Feedback required')) {
    status = 400;
    code = 'feedback_required';
  }

  const errorResponse: ErrorResponse = {
    code,
    message,
    status_code: status,
  };

  if (details) {
    errorResponse.details = details;
  }

  return jsonResponse(errorResponse, status);
}
