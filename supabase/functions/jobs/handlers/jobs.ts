import type { CascadeInfoResponse, HandlerContext, JobRecord } from '../types.ts';
import { camelToSnake, formatJobResponse, toSnakeCase } from '../utils.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { canPublishJobs } from '../middleware.ts';

// GET /job - List all tenant jobs
export async function listJobs(ctx: HandlerContext, _req: Request): Promise<Response> {
  const params = Object.fromEntries(ctx.url.searchParams);

  // Build query
  let query = ctx.supabaseUser
    .from('jobs')
    .select('*', { count: 'exact' })
    .eq('tenant_id', ctx.tenantId)
    .order(params.sortBy ? camelToSnake(params.sortBy) : 'created_at', {
      ascending: params.sortOrder === 'asc',
    });

  // Apply filters
  if (params.title) {
    query = query.ilike('title', `%${params.title}%`);
  }
  if (params.department) {
    query = query.eq('department', params.department);
  }
  if (params.location) {
    query = query.eq('location', params.location);
  }
  if (params.isPublic !== undefined) {
    query = query.eq('is_public', params.isPublic === 'true');
  }

  // Pagination
  const page = parseInt(params.page || '1', 10);
  const limit = Math.min(parseInt(params.limit || '50', 10), 100);
  const offset = (page - 1) * limit;
  query = query.range(offset, offset + limit - 1);

  const { data, error, count: _count } = await query;
  if (error) throw new Error(error.message);

  // Return array of jobs (matches NestJS response format)
  return jsonResponse((data as JobRecord[] || []).map(formatJobResponse));
}

// POST /job - Create new job
// Flow: Create as DRAFT → Assign pipeline → Update to ACTIVE
// If pipeline assignment fails, rollback (delete job)
export async function createJob(ctx: HandlerContext, req: Request): Promise<Response> {
  const body = await req.json();
  const dbData = toSnakeCase(body);

  // Extract pipeline_id if provided (optional)
  const pipelineId = body.pipelineId || body.pipeline_id;
  delete dbData.pipeline_id;

  // Remove fields that shouldn't be set on create
  delete dbData.id;
  delete dbData.created_at;
  delete dbData.updated_at;

  // 1. Create job as DRAFT
  const { data: job, error: createError } = await ctx.supabaseUser
    .from('jobs')
    .insert({
      ...dbData,
      tenant_id: ctx.tenantId,
      created_by: ctx.userId,
      status: 'DRAFT',
    })
    .select()
    .single();

  if (createError) throw new Error(createError.message);

  const jobId = (job as JobRecord).id;

  try {
    // 2. Call pipeline service to assign pipeline
    const pipelineResponse = await assignPipelineToJob(
      jobId,
      ctx.tenantId,
      pipelineId,
    );

    if (!pipelineResponse.ok) {
      const errorBody = await pipelineResponse.json().catch(() => ({}));
      const errorMsg = errorBody.message || `Pipeline assignment failed with status ${pipelineResponse.status}`;
      throw new Error(errorMsg);
    }

    // 3. Update job status to ACTIVE
    const { data: updatedJob, error: updateError } = await ctx.supabaseUser
      .from('jobs')
      .update({ status: 'ACTIVE' })
      .eq('id', jobId)
      .eq('tenant_id', ctx.tenantId)
      .select()
      .single();

    if (updateError) throw new Error(updateError.message);

    return jsonResponse(formatJobResponse(updatedJob as JobRecord), 201);
  } catch (error) {
    // 4. Rollback: Delete the DRAFT job on any failure
    await ctx.supabaseAdmin
      .from('jobs')
      .delete()
      .eq('id', jobId);

    throw error;
  }
}

// Internal: Call pipeline service to assign pipeline to job
async function assignPipelineToJob(
  jobId: string,
  tenantId: string,
  pipelineId?: string,
): Promise<Response> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ||
    Deno.env.get('SUPABASE_SECRET_KEY') || '';

  const pipelineUrl = `${supabaseUrl}/functions/v1/pipeline/pipeline/assign`;

  const requestBody: Record<string, string> = {
    job_id: jobId,
    tenant_id: tenantId,
  };

  if (pipelineId) {
    requestBody.pipeline_id = pipelineId;
  }

  return await fetch(pipelineUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${serviceRoleKey}`,
      'apikey': serviceRoleKey,
    },
    body: JSON.stringify(requestBody),
  });
}

// GET /job/:id - Get job by ID
export async function getJob(ctx: HandlerContext): Promise<Response> {
  const jobId = ctx.pathParts[1];

  const { data, error } = await ctx.supabaseUser
    .from('jobs')
    .select('*')
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (error || !data) {
    throw new Error(`Job with ID ${jobId} not found for tenant ${ctx.tenantId}`);
  }

  return jsonResponse(formatJobResponse(data as JobRecord));
}

// PUT /job/:id - Update job
export async function updateJob(ctx: HandlerContext, req: Request): Promise<Response> {
  const jobId = ctx.pathParts[1];
  const body = await req.json();
  const dbData = toSnakeCase(body);

  // Remove fields that shouldn't be updated
  delete dbData.id;
  delete dbData.tenant_id;
  delete dbData.created_at;
  delete dbData.updated_at;
  delete dbData.created_by;

  // Only include defined values
  const updates: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(dbData)) {
    if (value !== undefined) {
      updates[key] = value;
    }
  }

  const { data, error } = await ctx.supabaseUser
    .from('jobs')
    .update(updates)
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (error || !data) {
    throw new Error(`Job with ID ${jobId} not found for tenant ${ctx.tenantId}`);
  }

  return jsonResponse(formatJobResponse(data as JobRecord));
}

// DELETE /job/:id - Delete job (cascades to applications)
export async function deleteJob(ctx: HandlerContext): Promise<Response> {
  const jobId = ctx.pathParts[1];

  // First verify the job exists and belongs to tenant
  const { data: job, error: fetchError } = await ctx.supabaseUser
    .from('jobs')
    .select('id')
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !job) {
    throw new Error(`Job with ID ${jobId} not found for tenant ${ctx.tenantId}`);
  }

  // Delete the job (applications will cascade due to FK constraint)
  const { error } = await ctx.supabaseUser
    .from('jobs')
    .delete()
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId);

  if (error) throw new Error(error.message);

  // Return empty response to match NestJS behavior (void return)
  return new Response(null, { status: 204 });
}

// GET /job/:id/cascade-info - Get cascade deletion info
export async function getCascadeInfo(ctx: HandlerContext): Promise<Response> {
  const jobId = ctx.pathParts[1];

  // Verify job exists and belongs to tenant
  const { data: job, error: jobError } = await ctx.supabaseUser
    .from('jobs')
    .select('id')
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (jobError || !job) {
    throw new Error(`Job with ID ${jobId} not found for tenant ${ctx.tenantId}`);
  }

  // Count total applications for this job
  const { count: applicationCount } = await ctx.supabaseUser
    .from('applications')
    .select('id', { count: 'exact', head: true })
    .eq('job_id', jobId)
    .eq('tenant_id', ctx.tenantId);

  const result: CascadeInfoResponse = {
    jobId,
    applicationCount: applicationCount || 0,
  };

  return jsonResponse({ data: result });
}

// PUT /job/:id/publish - Publish job (ADMIN/HR only)
export async function publishJob(ctx: HandlerContext): Promise<Response> {
  if (!canPublishJobs(ctx.userRole || '')) {
    throw new Error('Forbidden: ADMIN or HR role required');
  }

  const jobId = ctx.pathParts[1];

  // First get the job to check if publishAt is already set
  const { data: existingJob, error: fetchError } = await ctx.supabaseUser
    .from('jobs')
    .select('*')
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !existingJob) {
    throw new Error(`Job with ID ${jobId} not found for tenant ${ctx.tenantId}`);
  }

  // Only set publishAt if not already set (matches NestJS logic)
  const updates: Record<string, unknown> = { is_public: true };
  if (!existingJob.publish_at) {
    updates.publish_at = new Date().toISOString();
  }

  const { data, error } = await ctx.supabaseUser
    .from('jobs')
    .update(updates)
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (error) throw new Error(error.message);
  return jsonResponse(formatJobResponse(data as JobRecord));
}

// PUT /job/:id/unpublish - Unpublish job (ADMIN/HR only)
export async function unpublishJob(ctx: HandlerContext): Promise<Response> {
  if (!canPublishJobs(ctx.userRole || '')) {
    throw new Error('Forbidden: ADMIN or HR role required');
  }

  const jobId = ctx.pathParts[1];

  const { data, error } = await ctx.supabaseUser
    .from('jobs')
    .update({ is_public: false })
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (error || !data) {
    throw new Error(`Job with ID ${jobId} not found for tenant ${ctx.tenantId}`);
  }

  return jsonResponse(formatJobResponse(data as JobRecord));
}
