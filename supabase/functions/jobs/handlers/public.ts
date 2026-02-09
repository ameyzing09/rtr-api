import type {
  HandlerContext,
  JobRecord,
  PublicJobsResponse,
  PublicJobDetailDto,
  PublicApplicationStatusResponse,
} from '../types.ts';
import { formatPublicJobDto, formatPublicJobDetailDto, attachToTrackingService } from '../utils.ts';
import { jsonResponse } from '../../_shared/cors.ts';

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

  // Search filter (across title, description, department, location)
  if (params.search) {
    const escapedSearch = params.search.replace(/%/g, '\\%').replace(/_/g, '\\_');
    const searchTerm = `%${escapedSearch}%`;
    query = query.or(`title.ilike.${searchTerm},description.ilike.${searchTerm},department.ilike.${searchTerm},location.ilike.${searchTerm}`);
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

// POST /public/jobs/:jobId/apply - Apply to a public job
export async function applyToJob(ctx: HandlerContext, req: Request): Promise<Response> {
  const jobId = ctx.pathParts[2]; // /public/jobs/:jobId/apply
  if (!jobId) {
    throw new Error('Job ID is required');
  }

  const body = await req.json();

  // Validate required fields
  if (!body.applicant_name || typeof body.applicant_name !== 'string' || !body.applicant_name.trim()) {
    throw new Error('applicant_name is required');
  }
  if (!body.applicant_email || typeof body.applicant_email !== 'string' || !body.applicant_email.trim()) {
    throw new Error('applicant_email is required');
  }

  const email = body.applicant_email.trim().toLowerCase();
  const name = body.applicant_name.trim();

  // Rate limit check: max 5 applications per email per tenant in 15 minutes
  const fifteenMinAgo = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count: recentCount, error: rateLimitError } = await ctx.supabaseAdmin
    .from('applications')
    .select('id', { count: 'exact', head: true })
    .eq('tenant_id', ctx.tenantId)
    .eq('applicant_email', email)
    .gte('created_at', fifteenMinAgo);

  if (rateLimitError) {
    console.error('Rate limit check failed:', rateLimitError.message);
  }

  if ((recentCount ?? 0) >= 5) {
    throw new Error('Too many applications submitted recently. Please try again later.');
  }

  // Extract IP and user-agent for audit
  const ipAddress = req.headers.get('x-forwarded-for')
    || req.headers.get('x-real-ip')
    || 'unknown';
  const userAgent = req.headers.get('user-agent') || 'unknown';

  // Call atomic RPC
  const { data: rpcResult, error: rpcError } = await ctx.supabaseAdmin
    .rpc('create_public_application_v1', {
      p_tenant_id: ctx.tenantId,
      p_job_id: jobId,
      p_applicant_name: name,
      p_applicant_email: email,
      p_applicant_phone: body.applicant_phone || null,
      p_resume_url: body.resume_url || null,
      p_cover_letter: body.cover_letter || null,
      p_ip_address: ipAddress,
      p_user_agent: userAgent,
    });

  if (rpcError) {
    // Surface job-not-found errors as 404
    if (rpcError.message.includes('not found') || rpcError.message.includes('not available')) {
      throw new Error('Job not found or not available for applications');
    }
    throw new Error(rpcError.message);
  }

  const result = Array.isArray(rpcResult) ? rpcResult[0] : rpcResult;

  if (!result || !result.application_id) {
    throw new Error('Application submission failed - unexpected response');
  }

  // If new application, attach to tracking pipeline
  if (result.is_new) {
    const trackingAttached = await attachToTrackingService(result.application_id, ctx.tenantId);

    if (!trackingAttached) {
      // Rollback: delete token and application on tracking failure
      await ctx.supabaseAdmin
        .from('candidate_access_tokens')
        .delete()
        .eq('application_id', result.application_id);
      await ctx.supabaseAdmin
        .from('applications')
        .delete()
        .eq('id', result.application_id);
      throw new Error('Application submission failed - please try again');
    }
  }

  return jsonResponse(
    {
      id: result.application_id,
      status: 'PENDING',
      candidate_access_token: result.access_token,
    },
    result.is_new ? 201 : 200
  );
}

// GET /public/applications/:token - Get application status by candidate access token
export async function getApplicationByToken(ctx: HandlerContext): Promise<Response> {
  const token = ctx.pathParts[2]; // /public/applications/:token

  // UUID format check — malformed tokens get the same 404 as missing ones
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(token)) {
    throw new Error('Application not found');
  }

  // Pre-validate token existence and expiry for distinct error messages
  const { data: tokenRow, error: tokenError } = await ctx.supabaseAdmin
    .from('candidate_access_tokens')
    .select('expires_at')
    .eq('token', token)
    .single();

  if (tokenError || !tokenRow) {
    throw new Error('Application not found');
  }

  if (new Date(tokenRow.expires_at) <= new Date()) {
    throw new Error('Access token has expired. Please reapply or contact the recruiter.');
  }

  const { data, error } = await ctx.supabaseAdmin
    .rpc('get_application_by_token_v1', { p_token: token });

  if (error) {
    throw new Error('Application not found');
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new Error('Application not found');
  }

  const response: PublicApplicationStatusResponse = {
    jobTitle: row.job_title,
    status: row.status_display_name,
    stageName: row.current_stage,
    appliedAt: row.applied_at,
    lastUpdatedAt: row.last_updated_at,
  };

  return jsonResponse(response);
}
