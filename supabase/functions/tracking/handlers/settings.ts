import type { CreateStatusDTO, HandlerContext, TenantStatusRecord, UpdateTenantStatusDTO } from '../types.ts';
import { formatStatusResponse, isValidUUID, jsonResponse } from '../utils.ts';

// ============================================================================
// GET /settings/statuses - List all statuses for tenant
// ============================================================================
export async function listStatuses(ctx: HandlerContext): Promise<Response> {
  const { data, error } = await ctx.supabaseAdmin
    .from('tenant_application_statuses')
    .select('*')
    .eq('tenant_id', ctx.tenantId)
    .eq('is_active', true)
    .order('sort_order');

  if (error) {
    throw new Error(`Failed to fetch statuses: ${error.message}`);
  }

  const statuses = (data as TenantStatusRecord[]).map(formatStatusResponse);

  return jsonResponse({ data: statuses });
}

// ============================================================================
// POST /settings/statuses - Create a new status
// ============================================================================
export async function createStatus(ctx: HandlerContext, req: Request): Promise<Response> {
  const body: CreateStatusDTO = await req.json();

  // Validation
  if (!body.status_code || typeof body.status_code !== 'string') {
    throw new Error('status_code is required');
  }
  if (!body.display_name || typeof body.display_name !== 'string') {
    throw new Error('display_name is required');
  }

  // Normalize status_code: uppercase, underscores for spaces
  const statusCode = body.status_code
    .toUpperCase()
    .trim()
    .replace(/\s+/g, '_')
    .replace(/[^A-Z0-9_]/g, '');

  if (statusCode.length < 2 || statusCode.length > 50) {
    throw new Error('status_code must be 2-50 characters');
  }

  // Generate action_code if not provided
  const actionCode = body.action_code ? body.action_code.toUpperCase().trim().replace(/\s+/g, '_') : statusCode;

  // Validate outcome_type if provided
  const validOutcomeTypes = ['ACTIVE', 'HOLD', 'SUCCESS', 'FAILURE', 'NEUTRAL'];
  const outcomeType = body.outcome_type ? body.outcome_type.toUpperCase().trim() : 'NEUTRAL';

  if (!validOutcomeTypes.includes(outcomeType)) {
    throw new Error(`outcome_type must be one of: ${validOutcomeTypes.join(', ')}`);
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('tenant_application_statuses')
    .insert({
      tenant_id: ctx.tenantId,
      status_code: statusCode,
      display_name: body.display_name.trim(),
      action_code: actionCode,
      outcome_type: outcomeType,
      is_terminal: body.is_terminal ?? false,
      sort_order: body.sort_order ?? 99,
      color_hex: body.color_hex || null,
    })
    .select()
    .single();

  if (error) {
    if (error.code === '23505') {
      throw new Error(`Status "${statusCode}" already exists for this tenant (conflict)`);
    }
    throw new Error(`Failed to create status: ${error.message}`);
  }

  return jsonResponse(
    { data: formatStatusResponse(data as TenantStatusRecord) },
    201,
  );
}

// ============================================================================
// PATCH /settings/statuses/:id - Update a status
// ============================================================================
export async function updateStatus(ctx: HandlerContext, req: Request): Promise<Response> {
  const statusId = ctx.pathParts[2];

  if (!isValidUUID(statusId)) {
    throw new Error('Invalid status ID format');
  }

  const body: UpdateTenantStatusDTO = await req.json();

  // Verify status exists and belongs to tenant
  const { data: existing, error: fetchError } = await ctx.supabaseAdmin
    .from('tenant_application_statuses')
    .select('*')
    .eq('id', statusId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !existing) {
    throw new Error(`Status not found`);
  }

  // Build update object with only provided fields
  const updates: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (body.display_name !== undefined) {
    updates.display_name = body.display_name.trim();
  }

  if (body.action_code !== undefined) {
    updates.action_code = body.action_code.toUpperCase().trim().replace(/\s+/g, '_');
  }

  if (body.is_terminal !== undefined) {
    // Check if changing terminal status and status is in use
    if (existing.is_terminal !== body.is_terminal) {
      const { count } = await ctx.supabaseAdmin
        .from('application_pipeline_state')
        .select('*', { count: 'exact', head: true })
        .eq('tenant_id', ctx.tenantId)
        .eq('status', existing.status_code);

      if ((count ?? 0) > 0 && !body.is_terminal) {
        throw new Error(
          `Cannot make status non-terminal - ${count} applications are using this status. ` +
            `Making it non-terminal would allow status changes from applications that should be final.`,
        );
      }
    }
    updates.is_terminal = body.is_terminal;
  }

  if (body.outcome_type !== undefined) {
    const validOutcomeTypes = ['ACTIVE', 'HOLD', 'SUCCESS', 'FAILURE', 'NEUTRAL'];
    const ot = body.outcome_type.toUpperCase().trim();
    if (!validOutcomeTypes.includes(ot)) {
      throw new Error(`outcome_type must be one of: ${validOutcomeTypes.join(', ')}`);
    }
    updates.outcome_type = ot;
  }

  if (body.sort_order !== undefined) {
    updates.sort_order = body.sort_order;
  }

  if (body.color_hex !== undefined) {
    updates.color_hex = body.color_hex || null;
  }

  const { data, error } = await ctx.supabaseAdmin
    .from('tenant_application_statuses')
    .update(updates)
    .eq('id', statusId)
    .eq('tenant_id', ctx.tenantId)
    .select()
    .single();

  if (error) {
    throw new Error(`Failed to update status: ${error.message}`);
  }

  return jsonResponse({ data: formatStatusResponse(data as TenantStatusRecord) });
}

// ============================================================================
// DELETE /settings/statuses/:id - Soft delete a status
// ============================================================================
export async function deleteStatus(ctx: HandlerContext): Promise<Response> {
  const statusId = ctx.pathParts[2];

  if (!isValidUUID(statusId)) {
    throw new Error('Invalid status ID format');
  }

  // Verify status exists and belongs to tenant
  const { data: status, error: fetchError } = await ctx.supabaseAdmin
    .from('tenant_application_statuses')
    .select('status_code')
    .eq('id', statusId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (fetchError || !status) {
    throw new Error(`Status not found`);
  }

  // Check if status is in use by any applications
  const { count } = await ctx.supabaseAdmin
    .from('application_pipeline_state')
    .select('*', { count: 'exact', head: true })
    .eq('tenant_id', ctx.tenantId)
    .eq('status', status.status_code);

  if ((count ?? 0) > 0) {
    throw new Error(
      `Cannot delete status "${status.status_code}" - it is currently used by ${count} application(s). ` +
        `Move applications to a different status first.`,
    );
  }

  // Soft delete (set is_active = false)
  const { error } = await ctx.supabaseAdmin
    .from('tenant_application_statuses')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', statusId)
    .eq('tenant_id', ctx.tenantId);

  if (error) {
    throw new Error(`Failed to delete status: ${error.message}`);
  }

  return jsonResponse({ success: true, message: `Status "${status.status_code}" deleted` });
}
