import type {
  HandlerContext,
  AttachToPipelineDTO,
  MoveStageDTO,
  UpdateStatusDTO,
  ApplicationPipelineStateRecord,
  PipelineStageRecord,
} from '../types.ts';
import {
  jsonResponse,
  formatTrackingStateResponse,
  isTerminalStatus,
  getActionFromStatus,
  isValidUUID,
} from '../utils.ts';

// POST /applications/:id/attach - Attach application to pipeline
export async function attachToPipeline(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: AttachToPipelineDTO = await req.json();

  // For service role calls, tenant_id comes from body
  const tenantId = ctx.isServiceRole && body.tenant_id ? body.tenant_id : ctx.tenantId;

  // 1. Check if already attached (idempotency - return 409)
  const { data: existingState } = await ctx.supabaseAdmin
    .from('application_pipeline_state')
    .select('id')
    .eq('application_id', applicationId)
    .single();

  if (existingState) {
    throw new Error('Application already attached to a pipeline (conflict)');
  }

  // 2. Get application to verify it exists and get job_id
  const { data: application, error: appError } = await ctx.supabaseAdmin
    .from('applications')
    .select('id, job_id, tenant_id')
    .eq('id', applicationId)
    .single();

  if (appError || !application) {
    throw new Error(`Application with ID ${applicationId} not found`);
  }

  // Verify tenant access
  if (application.tenant_id !== tenantId) {
    throw new Error('Forbidden: Tenant access violation');
  }

  const jobId = application.job_id;

  // 3. Resolve pipeline - use provided pipeline_id or get from job assignment
  let pipelineId = body.pipeline_id;

  if (!pipelineId) {
    // Get pipeline from job assignment
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
  } else {
    // Verify provided pipeline exists
    const { data: pipeline, error: pipelineError } = await ctx.supabaseAdmin
      .from('pipelines')
      .select('id, tenant_id')
      .eq('id', pipelineId)
      .eq('is_deleted', false)
      .single();

    if (pipelineError || !pipeline) {
      throw new Error(`Pipeline with ID ${pipelineId} not found`);
    }

    // Verify tenant access (global pipelines allowed)
    if (pipeline.tenant_id !== null && pipeline.tenant_id !== tenantId) {
      throw new Error('Forbidden: Tenant access violation');
    }
  }

  // 4. Get first stage of pipeline (order_index = 0)
  const { data: firstStage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('pipeline_id', pipelineId)
    .eq('order_index', 0)
    .single();

  if (stageError || !firstStage) {
    throw new Error('Pipeline has no stages configured');
  }

  // 5. Insert application_pipeline_state
  const { data: state, error: insertError } = await ctx.supabaseAdmin
    .from('application_pipeline_state')
    .insert({
      tenant_id: tenantId,
      application_id: applicationId,
      job_id: jobId,
      pipeline_id: pipelineId,
      current_stage_id: firstStage.id,
      status: 'ACTIVE',
      entered_stage_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (insertError) {
    throw new Error(`Failed to attach application: ${insertError.message}`);
  }

  // 6. Insert initial history entry
  await ctx.supabaseAdmin
    .from('application_stage_history')
    .insert({
      tenant_id: tenantId,
      application_id: applicationId,
      pipeline_id: pipelineId,
      from_stage_id: null,
      to_stage_id: firstStage.id,
      action: 'MOVE',
      changed_by: ctx.userId || null,
      reason: 'Application attached to pipeline',
    });

  return jsonResponse(
    formatTrackingStateResponse(state as ApplicationPipelineStateRecord, firstStage as PipelineStageRecord),
    201
  );
}

// GET /applications/:id - Get tracking state
export async function getState(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Get state with current stage info
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

  return jsonResponse({
    data: formatTrackingStateResponse(state as ApplicationPipelineStateRecord, stage as PipelineStageRecord),
  });
}

// POST /applications/:id/move - Move to different stage
export async function moveStage(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: MoveStageDTO = await req.json();

  if (!body.to_stage_id || !isValidUUID(body.to_stage_id)) {
    throw new Error('to_stage_id is required and must be a valid UUID');
  }

  // 1. Get current state
  const { data: state, error: stateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .select('*')
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (stateError || !state) {
    throw new Error(`Tracking state for application ${applicationId} not found`);
  }

  // 2. Check if status is terminal
  if (isTerminalStatus(state.status)) {
    throw new Error(`Cannot move application: status is terminal (${state.status})`);
  }

  // 3. Validate target stage exists in same pipeline
  const { data: targetStage, error: targetError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', body.to_stage_id)
    .eq('pipeline_id', state.pipeline_id)
    .single();

  if (targetError || !targetStage) {
    throw new Error(`Stage ${body.to_stage_id} not found in pipeline ${state.pipeline_id}`);
  }

  // 4. Update state
  const { data: updatedState, error: updateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .update({
      current_stage_id: body.to_stage_id,
      entered_stage_at: new Date().toISOString(),
    })
    .eq('id', state.id)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (updateError) {
    throw new Error(`Failed to move stage: ${updateError.message}`);
  }

  // 5. Insert history entry
  await ctx.supabaseAdmin
    .from('application_stage_history')
    .insert({
      tenant_id: ctx.tenantId,
      application_id: applicationId,
      pipeline_id: state.pipeline_id,
      from_stage_id: state.current_stage_id,
      to_stage_id: body.to_stage_id,
      action: 'MOVE',
      changed_by: ctx.userId,
      reason: body.reason || null,
    });

  return jsonResponse({
    data: formatTrackingStateResponse(updatedState as ApplicationPipelineStateRecord, targetStage as PipelineStageRecord),
  });
}

// PATCH /applications/:id/status - Update status
export async function updateStatus(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: UpdateStatusDTO = await req.json();

  const validStatuses = ['ACTIVE', 'HIRED', 'REJECTED', 'WITHDRAWN', 'ON_HOLD'];
  if (!body.status || !validStatuses.includes(body.status)) {
    throw new Error(`status must be one of: ${validStatuses.join(', ')}`);
  }

  // 1. Get current state
  const { data: state, error: stateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .select('*')
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (stateError || !state) {
    throw new Error(`Tracking state for application ${applicationId} not found`);
  }

  // 2. Check if current status is terminal (can't change)
  if (isTerminalStatus(state.status)) {
    throw new Error(`Cannot change status: current status is terminal (${state.status})`);
  }

  // 3. Update status
  const { data: updatedState, error: updateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .update({
      status: body.status,
    })
    .eq('id', state.id)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (updateError) {
    throw new Error(`Failed to update status: ${updateError.message}`);
  }

  // 4. Get current stage for response
  const { data: stage } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', state.current_stage_id)
    .single();

  // 5. Insert history entry
  await ctx.supabaseAdmin
    .from('application_stage_history')
    .insert({
      tenant_id: ctx.tenantId,
      application_id: applicationId,
      pipeline_id: state.pipeline_id,
      from_stage_id: state.current_stage_id,
      to_stage_id: state.current_stage_id,  // Same stage
      action: getActionFromStatus(body.status),
      changed_by: ctx.userId,
      reason: body.reason || null,
    });

  return jsonResponse({
    data: formatTrackingStateResponse(updatedState as ApplicationPipelineStateRecord, stage as PipelineStageRecord),
  });
}
