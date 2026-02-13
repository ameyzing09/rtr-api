import type {
  CreateEvaluationTemplateDTO,
  EvaluationTemplateRecord,
  EvaluationTemplateResponse,
  HandlerContext,
  UpdateEvaluationTemplateDTO,
} from '../types.ts';
import { isValidUUID, jsonResponse } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatTemplateResponse(record: EvaluationTemplateRecord): EvaluationTemplateResponse {
  return {
    id: record.id,
    name: record.name,
    description: record.description,
    version: record.version,
    isLatest: record.is_latest,
    participantType: record.participant_type,
    signalSchema: record.signal_schema,
    defaultAggregation: record.default_aggregation,
    isActive: record.is_active,
    createdAt: record.created_at,
  };
}

// ============================================================================
// TEMPLATE HANDLERS
// ============================================================================

// GET /settings/evaluation-templates
export async function listEvaluationTemplates(ctx: HandlerContext): Promise<Response> {
  const includeInactive = ctx.url.searchParams.get('include_inactive') === 'true';

  let query = ctx.supabaseAdmin
    .from('evaluation_templates')
    .select('*')
    .eq('tenant_id', ctx.tenantId)
    .eq('is_latest', true)
    .order('name');

  if (!includeInactive) {
    query = query.eq('is_active', true);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Failed to fetch templates: ${error.message}`);
  }

  const formatted = (data || []).map((t: EvaluationTemplateRecord) => formatTemplateResponse(t));

  return jsonResponse({ data: formatted });
}

// POST /settings/evaluation-templates
export async function createEvaluationTemplate(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const body: CreateEvaluationTemplateDTO = await req.json();

  // Validate required fields
  if (!body.name || body.name.trim() === '') {
    throw new Error('name is required');
  }
  if (!body.signal_schema || !Array.isArray(body.signal_schema)) {
    throw new Error('signal_schema is required and must be an array');
  }

  // Validate signal schema
  for (const signal of body.signal_schema) {
    if (!signal.key || !signal.type || !signal.label) {
      throw new Error('Each signal must have key, type, and label');
    }
    if (!['boolean', 'integer', 'float', 'text'].includes(signal.type)) {
      throw new Error(`Invalid signal type: ${signal.type}`);
    }
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .insert({
      tenant_id: ctx.tenantId,
      name: body.name.trim(),
      description: body.description || null,
      participant_type: body.participant_type || 'SINGLE',
      signal_schema: body.signal_schema,
      default_aggregation: body.default_aggregation || 'MAJORITY',
      created_by: ctx.userId,
    })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new Error('A template with this name already exists');
    }
    throw new Error(`Failed to create template: ${error.message}`);
  }

  return jsonResponse(
    { data: formatTemplateResponse(data as EvaluationTemplateRecord) },
    201,
  );
}

// PATCH /settings/evaluation-templates/:id
export async function updateEvaluationTemplate(
  ctx: HandlerContext,
  req: Request,
): Promise<Response> {
  const templateId = ctx.pathParts[2];

  if (!isValidUUID(templateId)) {
    throw new Error('Invalid template ID format');
  }

  const body: UpdateEvaluationTemplateDTO = await req.json();

  // Get current template
  const { data: current, error: fetchError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .select('*')
    .eq('id', templateId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !current) {
    throw new Error('Template not found');
  }

  const currentTemplate = current as EvaluationTemplateRecord;

  // Check if template is referenced by any instances
  const { count: instanceCount } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select('*', { count: 'exact', head: true })
    .eq('template_id', templateId);

  if (instanceCount && instanceCount > 0) {
    // Template is referenced - create new version
    // Only allow updating is_active on referenced templates without versioning
    if (body.is_active !== undefined && Object.keys(body).length === 1) {
      const { data: updated, error: updateError } = await ctx.supabaseAdmin
        .from('evaluation_templates')
        .update({ is_active: body.is_active })
        .eq('id', templateId)
        .select()
        .single();

      if (updateError) {
        throw new Error(`Failed to update template: ${updateError.message}`);
      }

      return jsonResponse({ data: formatTemplateResponse(updated as EvaluationTemplateRecord) });
    }

    // Create new version for structural changes
    // Mark old as not latest
    await ctx.supabaseAdmin
      .from('evaluation_templates')
      .update({ is_latest: false })
      .eq('id', templateId);

    // Create new version
    const { data: newVersion, error: createError } = await ctx.supabaseAdmin
      .from('evaluation_templates')
      .insert({
        tenant_id: ctx.tenantId,
        name: body.name?.trim() || currentTemplate.name,
        description: body.description !== undefined ? body.description : currentTemplate.description,
        version: currentTemplate.version + 1,
        is_latest: true,
        superseded_by: null,
        participant_type: body.participant_type || currentTemplate.participant_type,
        signal_schema: body.signal_schema || currentTemplate.signal_schema,
        default_aggregation: body.default_aggregation || currentTemplate.default_aggregation,
        is_active: body.is_active !== undefined ? body.is_active : currentTemplate.is_active,
        created_by: ctx.userId,
      })
      .select()
      .single();

    if (createError) {
      // Rollback is_latest change
      await ctx.supabaseAdmin
        .from('evaluation_templates')
        .update({ is_latest: true })
        .eq('id', templateId);

      throw new Error(`Failed to create new version: ${createError.message}`);
    }

    // Update old version's superseded_by
    await ctx.supabaseAdmin
      .from('evaluation_templates')
      .update({ superseded_by: (newVersion as EvaluationTemplateRecord).id })
      .eq('id', templateId);

    return jsonResponse({ data: formatTemplateResponse(newVersion as EvaluationTemplateRecord) });
  }

  // Template not referenced - update directly
  const updateData: Record<string, unknown> = {};
  if (body.name !== undefined) updateData.name = body.name.trim();
  if (body.description !== undefined) updateData.description = body.description;
  if (body.participant_type !== undefined) updateData.participant_type = body.participant_type;
  if (body.signal_schema !== undefined) updateData.signal_schema = body.signal_schema;
  if (body.default_aggregation !== undefined) updateData.default_aggregation = body.default_aggregation;
  if (body.is_active !== undefined) updateData.is_active = body.is_active;

  const { data: updated, error: updateError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .update(updateData)
    .eq('id', templateId)
    .select()
    .single();

  if (updateError) {
    throw new Error(`Failed to update template: ${updateError.message}`);
  }

  return jsonResponse({ data: formatTemplateResponse(updated as EvaluationTemplateRecord) });
}

// DELETE /settings/evaluation-templates/:id (soft delete)
export async function deleteEvaluationTemplate(ctx: HandlerContext): Promise<Response> {
  const templateId = ctx.pathParts[2];

  if (!isValidUUID(templateId)) {
    throw new Error('Invalid template ID format');
  }

  // Check if template exists and belongs to tenant
  const { data: current, error: fetchError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .select('id')
    .eq('id', templateId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !current) {
    throw new Error('Template not found');
  }

  // Soft delete
  const { error: updateError } = await ctx.supabaseAdmin
    .from('evaluation_templates')
    .update({ is_active: false })
    .eq('id', templateId);

  if (updateError) {
    throw new Error(`Failed to delete template: ${updateError.message}`);
  }

  return jsonResponse({ message: 'Template deleted successfully' });
}
