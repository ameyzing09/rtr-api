import type {
  HandlerContext,
  EvaluationTemplateRecord,
  EvaluationInstanceRecord,
  EvaluationInstanceResponse,
  MyPendingEvaluationResponse,
  CreateEvaluationInstanceDTO,
  CompleteEvaluationDTO,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatInstanceResponse(
  record: EvaluationInstanceRecord,
  templateName?: string,
  stageName?: string | null,
  participantCount?: number,
  submittedCount?: number
): EvaluationInstanceResponse {
  return {
    id: record.id,
    applicationId: record.application_id,
    templateId: record.template_id,
    templateName,
    stageId: record.stage_id,
    stageName,
    status: record.status,
    scheduledAt: record.scheduled_at,
    completedAt: record.completed_at,
    forceCompleted: record.force_completed,
    participantCount,
    submittedCount,
    createdAt: record.created_at,
    updatedAt: record.updated_at,
  };
}

// Handle RPC errors
function handleRpcError(error: { code?: string; message?: string }): never {
  const msg = error.message || 'Unknown error';

  if (msg.includes('NOT_FOUND')) {
    throw new Error('Not found: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('FORBIDDEN')) {
    throw new Error('Forbidden: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('INVALID_ACTION')) {
    throw new Error('Bad request: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('EVALUATION_INCOMPLETE')) {
    throw new Error('Bad request: ' + msg.split(': ').slice(1).join(': '));
  }
  if (msg.includes('VALIDATION')) {
    throw new Error('Bad request: ' + msg.split(': ').slice(1).join(': '));
  }

  throw new Error(msg);
}

// ============================================================================
// INSTANCE HANDLERS
// ============================================================================

// GET /applications/:id/evaluations
export async function listApplicationEvaluations(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select(`
      *,
      evaluation_templates!inner (
        name
      ),
      pipeline_stages (
        stage_name
      )
    `)
    .eq('tenant_id', ctx.tenantId)
    .eq('application_id', applicationId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(`Failed to fetch evaluations: ${error.message}`);
  }

  // Get participant counts for each instance
  const instanceIds = (data || []).map((d: Record<string, unknown>) => d.id);

  const { data: participants } = await ctx.supabaseAdmin
    .from('evaluation_participants')
    .select('evaluation_id, status')
    .in('evaluation_id', instanceIds);

  // Group participants by evaluation
  const participantsByEvaluation: Record<string, { total: number; submitted: number }> = {};
  for (const p of (participants || [])) {
    const pRecord = p as { evaluation_id: string; status: string };
    if (!participantsByEvaluation[pRecord.evaluation_id]) {
      participantsByEvaluation[pRecord.evaluation_id] = { total: 0, submitted: 0 };
    }
    participantsByEvaluation[pRecord.evaluation_id].total++;
    if (pRecord.status === 'SUBMITTED') {
      participantsByEvaluation[pRecord.evaluation_id].submitted++;
    }
  }

  const formatted = (data || []).map((d: Record<string, unknown>) => {
    const template = d.evaluation_templates as { name: string } | null;
    const stage = d.pipeline_stages as { stage_name: string } | null;
    const counts = participantsByEvaluation[d.id as string] || { total: 0, submitted: 0 };

    return formatInstanceResponse(
      d as unknown as EvaluationInstanceRecord,
      template?.name,
      stage?.stage_name || null,
      counts.total,
      counts.submitted
    );
  });

  return jsonResponse({ data: formatted });
}

// POST /applications/:id/evaluations
export async function createEvaluation(
  ctx: HandlerContext,
  req: Request
): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: CreateEvaluationInstanceDTO = await req.json();

  if (!body.template_id || !isValidUUID(body.template_id)) {
    throw new Error('template_id is required');
  }

  // Verify template exists and is active
  const { data: template, error: templateError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .select('*')
    .eq('id', body.template_id)
    .eq('tenant_id', ctx.tenantId)
    .eq('is_active', true)
    .single();

  if (templateError || !template) {
    throw new Error('Template not found or inactive');
  }

  // Verify application exists
  const { data: application } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!application) {
    throw new Error('Application not found');
  }

  // Create instance
  const { data: instance, error: createError } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .insert({
      tenant_id: ctx.tenantId,
      application_id: applicationId,
      template_id: body.template_id,
      stage_id: body.stage_id || null,
      scheduled_at: body.scheduled_at || null,
      created_by: ctx.userId,
    })
    .select()
    .single();

  if (createError) {
    throw new Error(`Failed to create evaluation: ${createError.message}`);
  }

  // Add initial participants if provided
  if (body.participant_ids && body.participant_ids.length > 0) {
    const participants = body.participant_ids.map((userId) => ({
      tenant_id: ctx.tenantId,
      evaluation_id: (instance as EvaluationInstanceRecord).id,
      user_id: userId,
    }));

    await ctx.supabaseAdmin
      .from('evaluation_participants')
      .insert(participants);
  }

  return jsonResponse(
    {
      data: formatInstanceResponse(
        instance as EvaluationInstanceRecord,
        (template as EvaluationTemplateRecord).name
      ),
    },
    201
  );
}

// POST /evaluations/:id/cancel
export async function cancelEvaluation(ctx: HandlerContext): Promise<Response> {
  const evaluationId = ctx.pathParts[1];

  if (!isValidUUID(evaluationId)) {
    throw new Error('Invalid evaluation ID format');
  }

  const { data: instance, error: fetchError } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select('*')
    .eq('id', evaluationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !instance) {
    throw new Error('Evaluation not found');
  }

  const currentInstance = instance as EvaluationInstanceRecord;

  if (currentInstance.status === 'COMPLETED') {
    throw new Error('Cannot cancel a completed evaluation');
  }

  if (currentInstance.status === 'CANCELLED') {
    throw new Error('Evaluation is already cancelled');
  }

  const { data: updated, error: updateError } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .update({ status: 'CANCELLED', updated_at: new Date().toISOString() })
    .eq('id', evaluationId)
    .select()
    .single();

  if (updateError) {
    throw new Error(`Failed to cancel evaluation: ${updateError.message}`);
  }

  return jsonResponse({ data: formatInstanceResponse(updated as EvaluationInstanceRecord) });
}

// POST /evaluations/:id/complete
export async function completeEvaluation(
  ctx: HandlerContext,
  req: Request
): Promise<Response> {
  const evaluationId = ctx.pathParts[1];

  if (!isValidUUID(evaluationId)) {
    throw new Error('Invalid evaluation ID format');
  }

  const body: CompleteEvaluationDTO = await req.json().catch(() => ({}));

  // Call RPC to complete evaluation (handles validation and signal aggregation)
  const { data, error } = await ctx.supabaseAdmin
    .rpc('complete_evaluation', {
      p_evaluation_id: evaluationId,
      p_user_id: ctx.userId,
      p_force: body.force || false,
      p_force_note: body.force_note || null,
    });

  if (error) {
    handleRpcError(error);
  }

  return jsonResponse({ data: formatInstanceResponse(data as EvaluationInstanceRecord) });
}

// GET /my-pending - List evaluations assigned to current user that are pending
export async function listMyPendingEvaluations(ctx: HandlerContext): Promise<Response> {
  // Query 1: Get evaluation IDs where this user is a pending participant
  const { data: participantRows, error: partError } = await ctx.supabaseAdmin
    .from('evaluation_participants')
    .select('evaluation_id, status')
    .eq('tenant_id', ctx.tenantId)
    .eq('user_id', ctx.userId!)
    .eq('status', 'PENDING');

  if (partError) {
    throw new Error(`Failed to fetch participant records: ${partError.message}`);
  }

  if (!participantRows || participantRows.length === 0) {
    return jsonResponse({ data: [] });
  }

  const evaluationIds = participantRows.map((p: { evaluation_id: string }) => p.evaluation_id);

  // Query 2: Get evaluation instances with template, stage, and application details
  const { data: evaluations, error: evalError } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select(`
      *,
      evaluation_templates!inner (
        name
      ),
      pipeline_stages (
        stage_name
      ),
      applications!inner (
        applicant_name,
        applicant_email
      )
    `)
    .eq('tenant_id', ctx.tenantId)
    .in('id', evaluationIds)
    .in('status', ['PENDING', 'IN_PROGRESS'])
    .order('created_at', { ascending: false });

  if (evalError) {
    throw new Error(`Failed to fetch evaluations: ${evalError.message}`);
  }

  const formatted: MyPendingEvaluationResponse[] = (evaluations || []).map(
    (d: Record<string, unknown>) => {
      const template = d.evaluation_templates as { name: string } | null;
      const stage = d.pipeline_stages as { stage_name: string } | null;
      const application = d.applications as { applicant_name: string; applicant_email: string } | null;

      return {
        evaluationId: d.id as string,
        applicationId: d.application_id as string,
        templateId: d.template_id as string,
        templateName: template?.name || '',
        stageId: (d.stage_id as string) || null,
        stageName: stage?.stage_name || null,
        evaluationStatus: d.status as MyPendingEvaluationResponse['evaluationStatus'],
        scheduledAt: (d.scheduled_at as string) || null,
        applicantName: application?.applicant_name || '',
        applicantEmail: application?.applicant_email || '',
        participantStatus: 'PENDING' as const,
        createdAt: d.created_at as string,
      };
    }
  );

  return jsonResponse({ data: formatted });
}
