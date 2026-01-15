import type {
  HandlerContext,
  PipelineStageRecord,
  ApplicationRecord,
  PipelineBoardResponse,
  BoardStageResponse,
  BoardApplicationResponse,
} from '../types.ts';
import { jsonResponse, formatStageResponse, isValidUUID } from '../utils.ts';

// GET /pipelines/:id/board - Get kanban board view for a pipeline
export async function getPipelineBoard(ctx: HandlerContext): Promise<Response> {
  const pipelineId = ctx.pathParts[1];

  if (!isValidUUID(pipelineId)) {
    throw new Error('Invalid pipeline ID format');
  }

  // Get query params
  const params = Object.fromEntries(ctx.url.searchParams);
  const statusFilter = params.status; // Optional: filter by status
  const jobIdFilter = params.jobId;   // Optional: filter by job

  // 1. Verify pipeline exists and get details
  const { data: pipeline, error: pipelineError } = await ctx.supabaseAdmin
    .from('pipelines')
    .select('id, name, tenant_id')
    .eq('id', pipelineId)
    .eq('is_deleted', false)
    .single();

  if (pipelineError || !pipeline) {
    throw new Error(`Pipeline with ID ${pipelineId} not found`);
  }

  // Verify tenant access (global pipelines allowed)
  if (pipeline.tenant_id !== null && pipeline.tenant_id !== ctx.tenantId) {
    throw new Error('Forbidden: Tenant access violation');
  }

  // 2. Get all stages for this pipeline (ordered)
  const { data: stages, error: stagesError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('pipeline_id', pipelineId)
    .order('order_index', { ascending: true });

  if (stagesError) {
    throw new Error(`Failed to fetch stages: ${stagesError.message}`);
  }

  // 3. Build query for application states
  let stateQuery = ctx.supabaseUser
    .from('application_pipeline_state')
    .select('*, applications(id, applicant_name, applicant_email)')
    .eq('pipeline_id', pipelineId)
    .eq('tenant_id', ctx.tenantId);

  // Apply filters
  if (statusFilter) {
    stateQuery = stateQuery.eq('status', statusFilter);
  }
  if (jobIdFilter) {
    stateQuery = stateQuery.eq('job_id', jobIdFilter);
  }

  const { data: states, error: statesError } = await stateQuery;

  if (statesError) {
    throw new Error(`Failed to fetch application states: ${statesError.message}`);
  }

  // 4. Group applications by stage
  const stageApplications = new Map<string, BoardApplicationResponse[]>();

  // Initialize all stages with empty arrays
  for (const stage of (stages || [])) {
    stageApplications.set(stage.id, []);
  }

  // Populate with applications
  for (const state of (states || [])) {
    const stageId = state.current_stage_id;
    const appList = stageApplications.get(stageId) || [];

    // Extract application info from join
    const app = (state as { applications?: ApplicationRecord }).applications;

    appList.push({
      applicationId: state.application_id,
      applicantName: app?.applicant_name || 'Unknown',
      applicantEmail: app?.applicant_email || 'Unknown',
      status: state.status,
      enteredStageAt: state.entered_stage_at,
    });

    stageApplications.set(stageId, appList);
  }

  // 5. Build response
  const boardStages: BoardStageResponse[] = (stages || []).map((stage) => {
    const applications = stageApplications.get(stage.id) || [];
    return {
      stage: formatStageResponse(stage as PipelineStageRecord),
      applications,
      count: applications.length,
    };
  });

  const response: PipelineBoardResponse = {
    pipelineId: pipelineId,
    pipelineName: pipeline.name,
    stages: boardStages,
    totalApplications: (states || []).length,
  };

  return jsonResponse({ data: response });
}
