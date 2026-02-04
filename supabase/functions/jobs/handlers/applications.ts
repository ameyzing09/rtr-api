import type { HandlerContext, ApplicationRecord } from '../types.ts';
import type { SupabaseClient } from '@supabase/supabase-js';
import { formatApplicationResponse, toSnakeCase } from '../utils.ts';
import { jsonResponse } from '../../_shared/cors.ts';

// Helper: Attach application to tracking service
// Returns true if successful, false if failed
async function attachToTrackingService(
  applicationId: string,
  tenantId: string,
  supabaseAdmin: SupabaseClient
): Promise<boolean> {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SECRET_KEY')
      || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error('Missing SUPABASE_URL or service role key');
      return false;
    }

    const trackingUrl = `${supabaseUrl}/functions/v1/tracking/applications/${applicationId}/attach`;

    const response = await fetch(trackingUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceRoleKey}`,
        'apikey': serviceRoleKey,
      },
      body: JSON.stringify({ tenant_id: tenantId }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Tracking attach failed: ${response.status} - ${errorText}`);
      return false;
    }

    return true;
  } catch (error) {
    console.error('Error calling tracking service:', error);
    return false;
  }
}

// GET /applications - List all tenant applications
export async function listApplications(ctx: HandlerContext, req: Request): Promise<Response> {
  const params = Object.fromEntries(ctx.url.searchParams);

  // Build query
  let query = ctx.supabaseUser
    .from('applications')
    .select('*', { count: 'exact' })
    .eq('tenant_id', ctx.tenantId)
    .order('created_at', { ascending: false });

  // Apply filters
  if (params.status) {
    query = query.eq('status', params.status);
  }
  if (params.jobId) {
    query = query.eq('job_id', params.jobId);
  }

  // Pagination
  const page = parseInt(params.page || '1', 10);
  const limit = Math.min(parseInt(params.limit || '50', 10), 100);
  const offset = (page - 1) * limit;
  query = query.range(offset, offset + limit - 1);

  const { data, error } = await query;
  if (error) throw new Error(error.message);

  // Return array of applications (matches NestJS response format)
  return jsonResponse((data as ApplicationRecord[] || []).map(formatApplicationResponse));
}

// POST /applications - Create new application (internal)
export async function createApplication(ctx: HandlerContext, req: Request): Promise<Response> {
  const body = await req.json();
  const dbData = toSnakeCase(body);

  // Verify job exists and belongs to tenant
  const { data: job, error: jobError } = await ctx.supabaseUser
    .from('jobs')
    .select('id')
    .eq('id', dbData.job_id)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (jobError || !job) {
    throw new Error(`Job with ID ${dbData.job_id} not found for tenant ${ctx.tenantId}`);
  }

  // Remove fields that shouldn't be set on create
  delete dbData.id;
  delete dbData.created_at;
  delete dbData.updated_at;

  const { data, error } = await ctx.supabaseUser
    .from('applications')
    .insert({
      ...dbData,
      tenant_id: ctx.tenantId,
      status: dbData.status || 'PENDING',
    })
    .select()
    .single();

  if (error) throw new Error(error.message);

  // Attach to tracking service (mandatory - no floating applications)
  const trackingAttached = await attachToTrackingService(
    data.id,
    ctx.tenantId,
    ctx.supabaseAdmin
  );

  if (!trackingAttached) {
    // Rollback: delete the application
    await ctx.supabaseAdmin
      .from('applications')
      .delete()
      .eq('id', data.id);
    throw new Error('Failed to attach application to pipeline - application rolled back');
  }

  return jsonResponse(formatApplicationResponse(data as ApplicationRecord), 201);
}

// GET /applications/:id - Get application by ID
export async function getApplication(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  const { data, error } = await ctx.supabaseUser
    .from('applications')
    .select('*')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (error || !data) {
    throw new Error(`Application with ID ${applicationId} not found for tenant ${ctx.tenantId}`);
  }

  return jsonResponse(formatApplicationResponse(data as ApplicationRecord));
}

// PUT /applications/:id - Update application
export async function updateApplication(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];
  const body = await req.json();
  const dbData = toSnakeCase(body);

  // Remove fields that shouldn't be updated
  delete dbData.id;
  delete dbData.tenant_id;
  delete dbData.created_at;
  delete dbData.updated_at;

  // Only include defined values
  const updates: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(dbData)) {
    if (value !== undefined) {
      updates[key] = value;
    }
  }

  const { data, error } = await ctx.supabaseUser
    .from('applications')
    .update(updates)
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (error || !data) {
    throw new Error(`Application with ID ${applicationId} not found for tenant ${ctx.tenantId}`);
  }

  return jsonResponse(formatApplicationResponse(data as ApplicationRecord));
}

// DELETE /applications/:id - Delete application
export async function deleteApplication(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  // First verify the application exists
  const { data: app, error: fetchError } = await ctx.supabaseUser
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !app) {
    throw new Error(`Application with ID ${applicationId} not found for tenant ${ctx.tenantId}`);
  }

  const { error } = await ctx.supabaseUser
    .from('applications')
    .delete()
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId);

  if (error) throw new Error(error.message);

  // Return empty response to match NestJS behavior (void return)
  return new Response(null, { status: 204 });
}
