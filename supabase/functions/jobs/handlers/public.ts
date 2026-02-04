import type {
  HandlerContext,
  JobRecord,
  PublicJobsResponse,
  PublicJobDetailDto,
  PublicApplicationResponse,
} from '../types.ts';
import { formatPublicJobDto, formatPublicJobDetailDto } from '../utils.ts';
import { jsonResponse } from '../../_shared/cors.ts';

// Helper: Attach application to tracking service
// Returns true if successful, false if failed
async function attachToTrackingService(
  applicationId: string,
  tenantId: string
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

// GET /public/jobs - List public jobs
export async function listPublicJobs(ctx: HandlerContext, req: Request): Promise<Response> {
  const params = Object.fromEntries(ctx.url.searchParams);
  const now = new Date().toISOString();

  // Build query for public jobs
  let query = ctx.supabaseAdmin
    .from('jobs')
    .select('id, tenant_id, title, department, location, description, extra, is_public, publish_at, expire_at, updated_at', { count: 'exact' })
    .eq('tenant_id', ctx.tenantId)
    .eq('is_public', true)
    .lte('publish_at', now)
    .or(`expire_at.is.null,expire_at.gte.${now}`)
    .order('publish_at', { ascending: false });

  // Search filter (across id, title, description, department, location)
  if (params.search) {
    const searchTerm = `%${params.search}%`;
    query = query.or(`id.ilike.${searchTerm},title.ilike.${searchTerm},description.ilike.${searchTerm},department.ilike.${searchTerm},location.ilike.${searchTerm}`);
  }

  // Department filter
  if (params.department) {
    query = query.eq('department', params.department);
  }

  // Location filter
  if (params.location) {
    query = query.eq('location', params.location);
  }

  // Pagination (matches NestJS default: page=1, pageSize=10)
  const page = parseInt(params.page || '1', 10);
  const pageSize = Math.min(parseInt(params.pageSize || '10', 10), 100);
  const offset = (page - 1) * pageSize;
  query = query.range(offset, offset + pageSize - 1);

  const { data, error, count } = await query;
  if (error) throw new Error(error.message);

  // Format response to match NestJS PublicJobsResponseDto
  const response: PublicJobsResponse = {
    data: (data as JobRecord[] || []).map(formatPublicJobDto),
    total: count || 0,
  };

  return jsonResponse(response);
}

// GET /public/jobs/:id - Get public job by ID
export async function getPublicJobById(ctx: HandlerContext): Promise<Response> {
  const jobId = ctx.pathParts[2]; // /public/jobs/:id
  const now = new Date().toISOString();

  const { data: job, error } = await ctx.supabaseAdmin
    .from('jobs')
    .select('id, tenant_id, title, department, location, description, extra, is_public, publish_at, expire_at, updated_at')
    .eq('id', jobId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (error || !job) {
    throw new Error(`Job with ID ${jobId} not found`);
  }

  // Validate job meets public criteria (matches NestJS logic)
  if (!job.is_public) {
    throw new Error(`Job with ID ${jobId} not found`);
  }

  if (!job.publish_at || job.publish_at > now) {
    throw new Error(`Job with ID ${jobId} not found`);
  }

  if (job.expire_at && job.expire_at < now) {
    throw new Error(`Job with ID ${jobId} not found`);
  }

  // Format response to match NestJS PublicJobDetailDto
  const response: PublicJobDetailDto = formatPublicJobDetailDto(job as JobRecord);
  return jsonResponse(response);
}

// POST /public/applications - Submit job application
export async function createPublicApplication(ctx: HandlerContext, req: Request): Promise<Response> {
  const body = await req.json();
  const now = new Date().toISOString();

  // Validate required fields (matches NestJS CreatePublicApplicationDto)
  if (!body.job_id) {
    throw new Error('job_id is required');
  }
  if (!body.applicant_name) {
    throw new Error('applicant_name is required');
  }
  if (!body.applicant_email) {
    throw new Error('applicant_email is required');
  }

  // Validate job exists, is public, and accepting applications
  const { data: job, error: jobError } = await ctx.supabaseAdmin
    .from('jobs')
    .select('id, is_public, publish_at, expire_at')
    .eq('id', body.job_id)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (jobError || !job) {
    throw new Error('Job not found or not available for applications');
  }

  // Validate job is public
  if (!job.is_public) {
    throw new Error('Job not found or not available for applications');
  }

  // Validate job is published
  if (!job.publish_at || job.publish_at > now) {
    throw new Error('Job not found or not available for applications');
  }

  // Validate job is not expired
  if (job.expire_at && job.expire_at < now) {
    throw new Error('Job not found or not available for applications');
  }

  // Create application with PENDING status
  const { data, error } = await ctx.supabaseAdmin
    .from('applications')
    .insert({
      tenant_id: ctx.tenantId,
      job_id: body.job_id,
      applicant_name: body.applicant_name,
      applicant_email: body.applicant_email,
      applicant_phone: body.applicant_phone || null,
      resume_url: body.resume_url || null,
      cover_letter: body.cover_letter || null,
      status: 'PENDING',
    })
    .select('id, status')
    .single();

  if (error) throw new Error(error.message);

  // Attach to tracking service (mandatory - no floating applications)
  const trackingAttached = await attachToTrackingService(data.id, ctx.tenantId);

  if (!trackingAttached) {
    // Rollback: delete the application
    await ctx.supabaseAdmin
      .from('applications')
      .delete()
      .eq('id', data.id);
    throw new Error('Application submission failed - please try again');
  }

  // Return minimal response matching NestJS PublicApplicationResponseDto
  const response: PublicApplicationResponse = {
    id: data.id,
    status: data.status,
  };

  return jsonResponse(response, 201);
}
