import type { HandlerContext, PipelineRecord, CreatePipelineDTO, UpdatePipelineDTO, PipelineAssignmentDTO } from '../types.ts';
import { formatPipelineResponse, jsonResponse, textResponse, validateStages, validateName, validateDescription } from '../utils.ts';
import { canManagePipelines } from '../middleware.ts';

// GET / - Health check
export function healthCheck(): Response {
  return textResponse('rtr-pipeline-engine-service: ok');
}

// GET /pipeline - List all pipelines (tenant-specific + global default)
export async function listPipelines(ctx: HandlerContext): Promise<Response> {
  const { data, error } = await ctx.supabaseAdmin
    .from('pipelines')
    .select('*')
    .or(`tenant_id.eq.${ctx.tenantId},tenant_id.is.null`)
    .eq('is_deleted', false)
    .order('created_at', { ascending: false });

  if (error) throw new Error(error.message);

  return jsonResponse((data as PipelineRecord[] || []).map(formatPipelineResponse));
}

// POST /pipeline - Create new pipeline
export async function createPipeline(ctx: HandlerContext, req: Request): Promise<Response> {
  if (!canManagePipelines(ctx.userRole || '')) {
    throw new Error('Forbidden: ADMIN or HR role required');
  }

  const body: CreatePipelineDTO = await req.json();

  // Validate required fields
  if (!validateName(body.name)) {
    throw new Error('name is required and must be 3-255 characters');
  }
  if (!validateStages(body.stages)) {
    throw new Error('stages must be a non-empty array with valid stage objects');
  }
  if (!validateDescription(body.description)) {
    throw new Error('description must be 1000 characters or less');
  }

  const { data, error } = await ctx.supabaseUser
    .from('pipelines')
    .insert({
      tenant_id: ctx.tenantId,
      name: body.name,
      description: body.description || null,
      stages: body.stages,
      is_active: true,
      is_deleted: false,
      created_by: ctx.userId,
    })
    .select()
    .single();

  if (error) {
    if (error.message.includes('unique') || error.code === '23505') {
      throw new Error('Pipeline with this name already exists for this tenant');
    }
    throw new Error(error.message);
  }

  // Return 200 per MIGRATION_SPEC (not 201)
  return jsonResponse(formatPipelineResponse(data as PipelineRecord), 200);
}

// GET /pipeline/:id - Get pipeline by ID
export async function getPipeline(ctx: HandlerContext): Promise<Response> {
  const pipelineId = ctx.pathParts[1];

  const { data, error } = await ctx.supabaseUser
    .from('pipelines')
    .select('*')
    .eq('id', pipelineId)
    .eq('tenant_id', ctx.tenantId)
    .eq('is_deleted', false)
    .single();

  if (error || !data) {
    throw new Error(`Pipeline with ID ${pipelineId} not found`);
  }

  // Return wrapped response per MIGRATION_SPEC
  return jsonResponse({ data: formatPipelineResponse(data as PipelineRecord) });
}

// PATCH /pipeline/:id - Update pipeline
export async function updatePipeline(ctx: HandlerContext, req: Request): Promise<Response> {
  if (!canManagePipelines(ctx.userRole || '')) {
    throw new Error('Forbidden: ADMIN or HR role required');
  }

  const pipelineId = ctx.pathParts[1];
  const body: UpdatePipelineDTO = await req.json();

  // Validate optional fields if provided
  if (body.name !== undefined && !validateName(body.name)) {
    throw new Error('name must be 3-255 characters');
  }
  if (body.stages !== undefined && !validateStages(body.stages)) {
    throw new Error('stages must be a non-empty array with valid stage objects');
  }
  if (body.description !== undefined && !validateDescription(body.description)) {
    throw new Error('description must be 1000 characters or less');
  }

  // Build update object with only provided fields
  const updates: Record<string, unknown> = {
    updated_by: ctx.userId,
  };

  if (body.name !== undefined) updates.name = body.name;
  if (body.description !== undefined) updates.description = body.description;
  if (body.stages !== undefined) updates.stages = body.stages;

  const { data, error } = await ctx.supabaseUser
    .from('pipelines')
    .update(updates)
    .eq('id', pipelineId)
    .eq('tenant_id', ctx.tenantId)
    .eq('is_deleted', false)
    .select()
    .single();

  if (error) {
    if (error.message.includes('unique') || error.code === '23505') {
      throw new Error('Pipeline with this name already exists for this tenant');
    }
    throw new Error(error.message);
  }

  if (!data) {
    throw new Error(`Pipeline with ID ${pipelineId} not found`);
  }

  // Return wrapped response per MIGRATION_SPEC
  return jsonResponse({ data: formatPipelineResponse(data as PipelineRecord) });
}

// GET /pipeline/job/:jobId - Get pipeline assigned to a job
export async function getPipelineByJob(ctx: HandlerContext): Promise<Response> {
  const jobId = ctx.pathParts[2]; // /pipeline/job/:jobId

  // Get assignment for this job
  const { data: assignment, error: assignError } = await ctx.supabaseAdmin
    .from('pipeline_assignments')
    .select('pipeline_id')
    .eq('job_id', jobId)
    .eq('is_deleted', false)
    .single();

  if (assignError || !assignment) {
    throw new Error(`No pipeline assigned to job ${jobId}`);
  }

  // Get the pipeline
  const { data: pipeline, error: pipelineError } = await ctx.supabaseAdmin
    .from('pipelines')
    .select('*')
    .eq('id', assignment.pipeline_id)
    .eq('is_deleted', false)
    .single();

  if (pipelineError || !pipeline) {
    throw new Error(`Pipeline not found`);
  }

  return jsonResponse({ data: formatPipelineResponse(pipeline as PipelineRecord) });
}

// POST /pipeline/assign - Assign pipeline to job
// Supports:
// - Optional pipeline_id (uses default if not provided)
// - Service role calls (internal service-to-service)
export async function assignPipeline(ctx: HandlerContext, req: Request): Promise<Response> {
  // Skip permission check for service role (internal calls)
  if (!ctx.isServiceRole && !canManagePipelines(ctx.userRole || '')) {
    throw new Error('Forbidden: ADMIN or HR role required');
  }

  const body: PipelineAssignmentDTO = await req.json();

  // Validate required fields
  if (!body.job_id) {
    throw new Error('job_id is required');
  }

  // For service role calls, tenant_id can come from body
  const tenantId = ctx.isServiceRole && body.tenant_id ? body.tenant_id : ctx.tenantId;

  // Determine pipeline_id
  let pipelineId = body.pipeline_id;

  if (!pipelineId) {
    // Find default pipeline (is_default = true, tenant_id = NULL)
    const { data: defaultPipeline, error: defaultError } = await ctx.supabaseAdmin
      .from('pipelines')
      .select('id')
      .eq('is_default', true)
      .is('tenant_id', null)
      .single();

    if (defaultError || !defaultPipeline) {
      throw new Error('No default pipeline configured');
    }
    pipelineId = defaultPipeline.id;
  } else {
    // Verify provided pipeline exists
    // Check both global (tenant_id = NULL) and tenant-specific pipelines
    const { data: pipeline, error: pipelineError } = await ctx.supabaseAdmin
      .from('pipelines')
      .select('id, tenant_id')
      .eq('id', pipelineId)
      .eq('is_deleted', false)
      .single();

    if (pipelineError || !pipeline) {
      throw new Error(`Pipeline with ID ${pipelineId} not found`);
    }

    // Verify tenant access (global pipelines allowed, or must match tenant)
    if (pipeline.tenant_id !== null && pipeline.tenant_id !== tenantId) {
      throw new Error('Forbidden: Tenant access violation');
    }
  }

  // Verify job exists and belongs to tenant
  const { data: job, error: jobError } = await ctx.supabaseAdmin
    .from('jobs')
    .select('id, tenant_id')
    .eq('id', body.job_id)
    .single();

  if (jobError || !job) {
    throw new Error(`Job with ID ${body.job_id} not found`);
  }

  // Verify job belongs to tenant
  if (job.tenant_id !== tenantId) {
    throw new Error('Forbidden: Tenant access violation');
  }

  // Create assignment using admin client (bypass RLS for internal calls)
  const { error } = await ctx.supabaseAdmin
    .from('pipeline_assignments')
    .insert({
      tenant_id: tenantId,
      pipeline_id: pipelineId,
      job_id: body.job_id,
      assigned_by: ctx.userId || null,
      is_deleted: false,
    });

  if (error) {
    if (error.message.includes('unique') || error.code === '23505') {
      throw new Error('Pipeline already assigned to this job');
    }
    throw new Error(error.message);
  }

  // Return 201 per MIGRATION_SPEC
  return jsonResponse({ message: 'Pipeline assigned successfully' }, 201);
}
