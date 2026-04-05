import type {
  ApplicationDetailResponse,
  ApplicationResponse,
  CandidateResponse,
  HandlerContext,
  JobResponse,
} from '../types.ts';
import { isValidUUID, jsonResponse } from '../utils.ts';
import { isInterviewerAssignedToApplication } from '../middleware.ts';
import { fetchApplication, fetchJob } from '../queries/application.ts';
import { fetchTrackingState } from '../queries/tracking.ts';
import { fetchInterviewSummaries } from '../queries/interviews.ts';
import { fetchEvaluationSummaries } from '../queries/evaluations.ts';
import { fetchTimelineEntries, buildRestrictedTimeline } from '../queries/timeline.ts';

// GET /applications/:id - Main application detail orchestrator
export async function getApplicationDetail(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  // Step 1: Validate UUID format
  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Step 2: Fetch application (validates existence + tenant)
  const application = await fetchApplication(
    ctx.supabaseAdmin,
    applicationId,
    ctx.tenantId,
  );

  // Step 3: INTERVIEWER assignment check
  const isRestricted = ctx.userRole === 'INTERVIEWER';

  if (isRestricted) {
    const isAssigned = await isInterviewerAssignedToApplication(
      ctx.supabaseAdmin,
      ctx.userId,
      ctx.tenantId,
      applicationId,
    );
    if (!isAssigned) {
      throw new Error('Forbidden: Not assigned to this application');
    }
  }

  // Parse timeline_limit from query params
  const timelineLimit = Math.min(
    Math.max(parseInt(ctx.url.searchParams.get('timeline_limit') || '50', 10) || 50, 1),
    200,
  );

  // Step 4: Parallel fetch all sections via Promise.all
  const [job, tracking, interviews, evaluations, timeline] = await Promise.all([
    // Job info
    fetchJob(ctx.supabaseAdmin, application.job_id, ctx.tenantId),

    // Tracking state
    fetchTrackingState(ctx.supabaseAdmin, applicationId, ctx.tenantId),

    // Interview summaries
    fetchInterviewSummaries(ctx.supabaseAdmin, applicationId, ctx.tenantId),

    // Evaluation summaries (filtered for INTERVIEWER)
    fetchEvaluationSummaries(
      ctx.supabaseAdmin,
      applicationId,
      ctx.tenantId,
      isRestricted,
      ctx.userId,
    ),

    // Timeline (restricted for INTERVIEWER)
    isRestricted
      ? buildRestrictedTimeline(ctx.supabaseAdmin, applicationId, ctx.tenantId, timelineLimit)
      : fetchTimelineEntries(ctx.supabaseAdmin, applicationId, ctx.tenantId, application, timelineLimit),
  ]);

  // Step 5: Compose response with field-level restrictions
  const applicationResponse: ApplicationResponse = {
    id: application.id,
    status: application.status,
    createdAt: application.created_at,
    updatedAt: application.updated_at,
    resumeUrl: isRestricted ? null : application.resume_url,
    coverLetter: isRestricted ? null : application.cover_letter,
  };

  const candidate: CandidateResponse = {
    name: application.applicant_name,
    email: application.applicant_email,
    phone: application.applicant_phone,
  };

  const jobResponse: JobResponse = {
    id: job.id,
    title: job.title,
    department: job.department ?? null,
    location: job.location ?? null,
  };

  const response: ApplicationDetailResponse = {
    viewerContext: {
      viewerRole: ctx.userRole,
      isRestricted,
    },
    application: applicationResponse,
    candidate,
    job: jobResponse,
    tracking,
    interviews,
    evaluations,
    timeline,
  };

  return jsonResponse({ data: response });
}
