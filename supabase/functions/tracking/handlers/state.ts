import type {
  HandlerContext,
  AttachToPipelineDTO,
  MoveStageDTO,
  UpdateStatusDTO,
  PipelineStageRecord,
  TrackingStateResponse,
} from '../types.ts';
import {
  jsonResponse,
  isValidUUID,
} from '../utils.ts';

// ============================================================================
// Type for RPC return (matches tracking_state_result composite type)
// ============================================================================
interface TrackingRpcResult {
  id: string;
  application_id: string;
  job_id: string;
  pipeline_id: string;
  current_stage_id: string;
  status: string;
  entered_stage_at: string;
  updated_at: string;
}

// Format RPC result to API response
function formatRpcResult(
  result: TrackingRpcResult,
  stage: PipelineStageRecord
): TrackingStateResponse {
  return {
    id: result.id,
    applicationId: result.application_id,
    jobId: result.job_id,
    pipelineId: result.pipeline_id,
    currentStageId: result.current_stage_id,
    currentStageName: stage.stage_name,
    currentStageIndex: stage.order_index,
    status: result.status,
    outcomeType: (result as Record<string, unknown>).outcome_type as string || 'ACTIVE',
    isTerminal: (result as Record<string, unknown>).is_terminal as boolean ?? false,
    enteredStageAt: result.entered_stage_at,
    createdAt: result.entered_stage_at, // RPC doesn't return created_at, use entered_stage_at
    updatedAt: result.updated_at,
  };
}

// Handle structured error codes from RPC
function handleRpcError(error: { code?: string; message?: string }): never {
  const msg = error.message || 'Unknown error';

  // Unique constraint violation (duplicate attach)
  if (error.code === '23505') {
    throw new Error('Application already attached to a pipeline (conflict)');
  }

  // Custom error codes from our functions
  if (msg.includes('TENANT_MISMATCH')) {
    throw new Error('Forbidden: Tenant access violation');
  }
  if (msg.includes('INVALID_STAGE')) {
    throw new Error('Bad request: Stage does not belong to pipeline');
  }
  if (msg.includes('INVALID_STATUS')) {
    // Extract status name from error message if possible
    const match = msg.match(/Status "([^"]+)" not configured/);
    const statusName = match ? match[1] : 'unknown';
    throw new Error(`Bad request: Status "${statusName}" is not configured for this tenant`);
  }
  if (msg.includes('NOT_FOUND')) {
    throw new Error('Not found: Application state not found');
  }
  if (msg.includes('TERMINAL_STATUS')) {
    throw new Error('Forbidden: Cannot modify application in terminal status');
  }

  throw new Error(msg);
}

// ============================================================================
// POST /applications/:id/attach - Attach application to pipeline
// ============================================================================
export async function attachToPipeline(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: AttachToPipelineDTO = await req.json();

  // For service role calls, tenant_id comes from body
  const tenantId = ctx.isServiceRole && body.tenant_id ? body.tenant_id : ctx.tenantId;

  // Get application to get job_id (RPC validates tenant ownership)
  const { data: application, error: appError } = await ctx.supabaseAdmin
    .from('applications')
    .select('id, job_id')
    .eq('id', applicationId)
    .single();

  if (appError || !application) {
    throw new Error(`Application with ID ${applicationId} not found`);
  }

  const jobId = application.job_id;

  // Resolve pipeline - use provided pipeline_id or get from job assignment
  let pipelineId = body.pipeline_id;

  if (!pipelineId) {
    const { data: assignment, error: assignError } = await ctx.supabaseAdmin
      .from('pipeline_assignments')
      .select('pipeline_id')
      .eq('job_id', jobId)
      .eq('is_deleted', false)
      .single();

    if (assignError || !assignment) {
      throw new Error(`No pipeline assigned to job ${jobId}`);
    }
    pipelineId = assignment.pipeline_id;
  }

  // Get first stage of pipeline (order_index = 0)
  const { data: firstStage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('pipeline_id', pipelineId)
    .eq('order_index', 0)
    .single();

  if (stageError || !firstStage) {
    throw new Error('Pipeline has no stages configured');
  }

  // Call atomic RPC (validates tenant, inserts state + history atomically)
  const { data: result, error: rpcError } = await ctx.supabaseAdmin
    .rpc('attach_application_to_pipeline_v1', {
      p_tenant_id: tenantId,
      p_application_id: applicationId,
      p_job_id: jobId,
      p_pipeline_id: pipelineId,
      p_first_stage_id: firstStage.id,
      p_user_id: ctx.userId || null,
    });

  if (rpcError) {
    handleRpcError(rpcError);
  }

  return jsonResponse(
    formatRpcResult(result as TrackingRpcResult, firstStage as PipelineStageRecord),
    201
  );
}

// ============================================================================
// GET /applications/:id - Get tracking state
// ============================================================================
export async function getState(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Get state with RLS
  const { data: state, error: stateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .select('*')
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (stateError || !state) {
    throw new Error(`Tracking state for application ${applicationId} not found`);
  }

  // Get current stage details
  const { data: stage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', state.current_stage_id)
    .single();

  if (stageError || !stage) {
    throw new Error('Current stage not found');
  }

  // Format manually since we're not using RPC
  const response: TrackingStateResponse = {
    id: state.id,
    applicationId: state.application_id,
    jobId: state.job_id,
    pipelineId: state.pipeline_id,
    currentStageId: state.current_stage_id,
    currentStageName: (stage as PipelineStageRecord).stage_name,
    currentStageIndex: (stage as PipelineStageRecord).order_index,
    status: state.status,
    outcomeType: state.outcome_type || 'ACTIVE',
    isTerminal: state.is_terminal ?? false,
    enteredStageAt: state.entered_stage_at,
    createdAt: state.created_at,
    updatedAt: state.updated_at,
  };

  return jsonResponse({ data: response });
}

// ============================================================================
// POST /applications/:id/move - Move to different stage
// DEPRECATED: Use POST /applications/:id/act with { action: "COMPLETE" }
// ============================================================================
export async function moveStage(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: MoveStageDTO = await req.json();

  if (!body.to_stage_id || !isValidUUID(body.to_stage_id)) {
    throw new Error('to_stage_id is required and must be a valid UUID');
  }

  // Call atomic RPC (validates everything, handles idempotency)
  const { data: result, error: rpcError } = await ctx.supabaseAdmin
    .rpc('move_application_stage_v1', {
      p_application_id: applicationId,
      p_tenant_id: ctx.tenantId,
      p_to_stage_id: body.to_stage_id,
      p_user_id: ctx.userId,
      p_reason: body.reason || null,
    });

  if (rpcError) {
    handleRpcError(rpcError);
  }

  // Get stage details for response
  const { data: stage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', body.to_stage_id)
    .single();

  if (stageError || !stage) {
    throw new Error('Stage not found');
  }

  return jsonResponse({
    data: formatRpcResult(result as TrackingRpcResult, stage as PipelineStageRecord),
  });
}

// ============================================================================
// PATCH /applications/:id/status - Update status
// DEPRECATED: Use POST /applications/:id/act with { action: "HIRE" | "FAIL" | ... }
// ============================================================================
export async function updateStatus(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: UpdateStatusDTO = await req.json();

  // Validation: status is required (RPC validates against tenant_application_statuses)
  if (!body.status || typeof body.status !== 'string' || body.status.trim() === '') {
    throw new Error('status is required');
  }

  // Call atomic RPC (validates everything, handles idempotency)
  const { data: result, error: rpcError } = await ctx.supabaseAdmin
    .rpc('update_application_status_v1', {
      p_application_id: applicationId,
      p_tenant_id: ctx.tenantId,
      p_status: body.status,
      p_user_id: ctx.userId,
      p_reason: body.reason || null,
    });

  if (rpcError) {
    handleRpcError(rpcError);
  }

  // Get stage details for response
  const rpcResult = result as TrackingRpcResult;
  const { data: stage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', rpcResult.current_stage_id)
    .single();

  if (stageError || !stage) {
    throw new Error('Stage not found');
  }

  return jsonResponse({
    data: formatRpcResult(rpcResult, stage as PipelineStageRecord),
  });
}
