import type {
  HandlerContext,
  StageEvaluationRecord,
  StageEvaluationResponse,
  CreateStageEvaluationDTO,
  UpdateStageEvaluationDTO,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatStageEvaluationResponse(
  record: StageEvaluationRecord,
  templateName?: string,
  stageName?: string
): StageEvaluationResponse {
  return {
    id: record.id,
    stageId: record.stage_id,
    evaluationTemplateId: record.evaluation_template_id,
    templateName,
    stageName,
    executionOrder: record.execution_order,
    autoCreate: record.auto_create,
    required: record.required,
    isActive: record.is_active,
    createdAt: record.created_at,
    updatedAt: record.updated_at,
  };
}

// ============================================================================
// STAGE EVALUATION HANDLERS
// ============================================================================

// GET /settings/stage-evaluations
export async function listStageEvaluations(ctx: HandlerContext): Promise<Response> {
  const stageId = ctx.url.searchParams.get('stage_id');
  const includeInactive = ctx.url.searchParams.get('include_inactive') === 'true';

  let query = ctx.supabaseAdmin
    .from('stage_evaluations')
    .select(`
      *,
      evaluation_templates!inner (
        name
      ),
      pipeline_stages!inner (
        stage_name
      )
    `)
    .eq('tenant_id', ctx.tenantId)
    .order('execution_order');

  if (stageId) {
    if (!isValidUUID(stageId)) {
      throw new Error('Invalid stage_id format');
    }
    query = query.eq('stage_id', stageId);
  }

  if (!includeInactive) {
    query = query.eq('is_active', true);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Failed to fetch stage evaluations: ${error.message}`);
  }

  const formatted = (data || []).map((d: Record<string, unknown>) => {
    const template = d.evaluation_templates as { name: string } | null;
    const stage = d.pipeline_stages as { stage_name: string } | null;
    return formatStageEvaluationResponse(
      d as unknown as StageEvaluationRecord,
      template?.name,
      stage?.stage_name
    );
  });

  return jsonResponse({ data: formatted });
}

// POST /settings/stage-evaluations
export async function createStageEvaluation(
  ctx: HandlerContext,
  req: Request
): Promise<Response> {
  const body: CreateStageEvaluationDTO = await req.json();

  // Validate required fields
  if (!body.stage_id || !isValidUUID(body.stage_id)) {
    throw new Error('stage_id is required and must be a valid UUID');
  }
  if (!body.evaluation_template_id || !isValidUUID(body.evaluation_template_id)) {
    throw new Error('evaluation_template_id is required and must be a valid UUID');
  }

  // Verify template exists and is active
  const { data: template, error: templateError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .select('id, name')
    .eq('id', body.evaluation_template_id)
    .eq('tenant_id', ctx.tenantId)
    .eq('is_active', true)
    .single();

  if (templateError || !template) {
    throw new Error('Template not found or inactive');
  }

  // Verify stage exists
  const { data: stage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('id, stage_name')
    .eq('id', body.stage_id)
    .single();

  if (stageError || !stage) {
    throw new Error('Stage not found');
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .insert({
      tenant_id: ctx.tenantId,
      stage_id: body.stage_id,
      evaluation_template_id: body.evaluation_template_id,
      execution_order: body.execution_order ?? 1,
      auto_create: body.auto_create ?? true,
      required: body.required ?? false,
    })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new Error('A stage evaluation with this configuration already exists');
    }
    throw new Error(`Failed to create stage evaluation: ${error.message}`);
  }

  return jsonResponse(
    {
      data: formatStageEvaluationResponse(
        data as StageEvaluationRecord,
        (template as { name: string }).name,
        (stage as { stage_name: string }).stage_name
      ),
    },
    201
  );
}

// PATCH /settings/stage-evaluations/:id
export async function updateStageEvaluation(
  ctx: HandlerContext,
  req: Request
): Promise<Response> {
  const stageEvalId = ctx.pathParts[2];

  if (!isValidUUID(stageEvalId)) {
    throw new Error('Invalid stage evaluation ID format');
  }

  const body: UpdateStageEvaluationDTO = await req.json();

  // Verify it exists and belongs to tenant
  const { data: current, error: fetchError } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .select('*')
    .eq('id', stageEvalId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !current) {
    throw new Error('Stage evaluation not found');
  }

  const updateData: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (body.execution_order !== undefined) updateData.execution_order = body.execution_order;
  if (body.auto_create !== undefined) updateData.auto_create = body.auto_create;
  if (body.required !== undefined) updateData.required = body.required;
  if (body.is_active !== undefined) updateData.is_active = body.is_active;

  const { data: updated, error: updateError } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .update(updateData)
    .eq('id', stageEvalId)
    .select(`
      *,
      evaluation_templates!inner (
        name
      ),
      pipeline_stages!inner (
        stage_name
      )
    `)
    .single();

  if (updateError) {
    throw new Error(`Failed to update stage evaluation: ${updateError.message}`);
  }

  const template = (updated as Record<string, unknown>).evaluation_templates as { name: string } | null;
  const stage = (updated as Record<string, unknown>).pipeline_stages as { stage_name: string } | null;

  return jsonResponse({
    data: formatStageEvaluationResponse(
      updated as unknown as StageEvaluationRecord,
      template?.name,
      stage?.stage_name
    ),
  });
}

// DELETE /settings/stage-evaluations/:id (soft delete)
export async function deleteStageEvaluation(ctx: HandlerContext): Promise<Response> {
  const stageEvalId = ctx.pathParts[2];
  const force = ctx.url.searchParams.get('force') === 'true';

  if (!isValidUUID(stageEvalId)) {
    throw new Error('Invalid stage evaluation ID format');
  }

  // Verify it exists and belongs to tenant
  const { data: current, error: fetchError } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .select('*')
    .eq('id', stageEvalId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !current) {
    throw new Error('Stage evaluation not found');
  }

  const currentRecord = current as StageEvaluationRecord;

  // Guard: check for active evaluation instances unless force=true
  if (!force) {
    const { count } = await ctx.supabaseAdmin
      .from('evaluation_instances')
      .select('*', { count: 'exact', head: true })
      .eq('tenant_id', ctx.tenantId)
      .eq('template_id', currentRecord.evaluation_template_id)
      .eq('stage_id', currentRecord.stage_id)
      .in('status', ['PENDING', 'IN_PROGRESS']);

    if (count && count > 0) {
      throw new Error(
        `Cannot deactivate: ${count} active evaluation instance(s) exist for this stage+template combo. Use ?force=true to override.`
      );
    }
  }

  // Soft delete
  const { error: updateError } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', stageEvalId);

  if (updateError) {
    throw new Error(`Failed to delete stage evaluation: ${updateError.message}`);
  }

  return jsonResponse({ message: 'Stage evaluation deactivated successfully' });
}
