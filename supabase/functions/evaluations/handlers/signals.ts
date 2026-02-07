import type {
  HandlerContext,
  ApplicationSignalRecord,
  ApplicationSignalResponse,
  SetManualSignalDTO,
} from '../types.ts';
import { jsonResponse, isValidUUID } from '../utils.ts';

// ============================================================================
// Format functions
// ============================================================================

function formatSignalResponse(record: ApplicationSignalRecord): ApplicationSignalResponse {
  // Determine the value based on signal type
  let value: string | number | boolean | null = null;
  if (record.signal_value_boolean !== null) {
    value = record.signal_value_boolean;
  } else if (record.signal_value_numeric !== null) {
    value = record.signal_value_numeric;
  } else if (record.signal_value_text !== null) {
    value = record.signal_value_text;
  }

  return {
    id: record.id,
    applicationId: record.application_id,
    signalKey: record.signal_key,
    signalType: record.signal_type,
    value,
    sourceType: record.source_type,
    sourceId: record.source_id,
    setBy: record.set_by,
    setAt: record.set_at,
  };
}

// Handle RPC errors
function handleRpcError(error: { code?: string; message?: string }): never {
  const msg = error.message || 'Unknown error';

  if (msg.includes('VALIDATION')) {
    throw new Error('Bad request: ' + msg.split(': ').slice(1).join(': '));
  }

  throw new Error(msg);
}

// ============================================================================
// SIGNAL HANDLERS
// ============================================================================

// GET /applications/:id/signals
export async function getApplicationSignals(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const includeHistory = ctx.url.searchParams.get('include_history') === 'true';

  // Verify application exists and belongs to tenant
  const { data: application } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!application) {
    throw new Error('Application not found');
  }

  if (includeHistory) {
    // Return full signal history
    const { data, error } = await ctx.supabaseAdmin
      .from('application_signals')
      .select('*')
      .eq('application_id', applicationId)
      .eq('tenant_id', ctx.tenantId)
      .order('signal_key')
      .order('set_at', { ascending: false });

    if (error) {
      throw new Error(`Failed to fetch signals: ${error.message}`);
    }

    // Group by signal key
    const grouped: Record<string, {
      current: ApplicationSignalResponse | null;
      history: ApplicationSignalResponse[];
    }> = {};

    for (const record of (data || []) as ApplicationSignalRecord[]) {
      const formatted = formatSignalResponse(record);

      if (!grouped[record.signal_key]) {
        grouped[record.signal_key] = { current: null, history: [] };
      }

      if (record.superseded_at === null) {
        grouped[record.signal_key].current = formatted;
      } else {
        grouped[record.signal_key].history.push(formatted);
      }
    }

    return jsonResponse({ data: grouped });
  }

  // Return only latest signals (using the view)
  const { data, error } = await ctx.supabaseAdmin
    .from('application_signals_latest')
    .select('*')
    .eq('application_id', applicationId)
    .order('signal_key');

  if (error) {
    throw new Error(`Failed to fetch signals: ${error.message}`);
  }

  const formatted = (data || []).map((s: ApplicationSignalRecord) =>
    formatSignalResponse(s)
  );

  return jsonResponse({ data: formatted });
}

// POST /applications/:id/signals (ADMIN only)
export async function setManualSignal(
  ctx: HandlerContext,
  req: Request
): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: SetManualSignalDTO = await req.json();

  // Validate required fields
  if (!body.signal_key || body.signal_key.trim() === '') {
    throw new Error('signal_key is required');
  }

  if (!body.signal_type || !['boolean', 'integer', 'float', 'text'].includes(body.signal_type)) {
    throw new Error('signal_type must be one of: boolean, integer, float, text');
  }

  if (body.value === undefined || body.value === null) {
    throw new Error('value is required');
  }

  // Validate value format based on type
  if (body.signal_type === 'boolean') {
    const lowerValue = body.value.toLowerCase();
    if (lowerValue !== 'true' && lowerValue !== 'false') {
      throw new Error('value must be "true" or "false" for boolean signals');
    }
  } else if (body.signal_type === 'integer' || body.signal_type === 'float') {
    const numValue = Number(body.value);
    if (isNaN(numValue)) {
      throw new Error('value must be a valid number for numeric signals');
    }
  }

  // Verify application exists and belongs to tenant
  const { data: application } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!application) {
    throw new Error('Application not found');
  }

  // Normalize signal key
  const normalizedKey = body.signal_key.toUpperCase().trim().replace(/\s+/g, '_');

  // Call RPC to set manual signal
  const { data, error } = await ctx.supabaseAdmin
    .rpc('set_manual_signal', {
      p_application_id: applicationId,
      p_tenant_id: ctx.tenantId,
      p_user_id: ctx.userId,
      p_signal_key: normalizedKey,
      p_signal_type: body.signal_type,
      p_value: body.value,
      p_note: body.note || null,
    });

  if (error) {
    handleRpcError(error);
  }

  return jsonResponse({ data: formatSignalResponse(data as ApplicationSignalRecord) }, 201);
}

// GET /applications/:id/signals/:key/history
export async function getSignalHistory(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];
  const signalKey = ctx.pathParts[3];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  if (!signalKey) {
    throw new Error('Signal key is required');
  }

  // Verify application exists and belongs to tenant
  const { data: application } = await ctx.supabaseAdmin
    .from('applications')
    .select('id')
    .eq('id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (!application) {
    throw new Error('Application not found');
  }

  const normalizedKey = signalKey.toUpperCase();

  const { data, error } = await ctx.supabaseAdmin
    .from('application_signals')
    .select('*')
    .eq('application_id', applicationId)
    .eq('signal_key', normalizedKey)
    .order('set_at', { ascending: false });

  if (error) {
    throw new Error(`Failed to fetch signal history: ${error.message}`);
  }

  const formatted = (data || []).map((s: ApplicationSignalRecord) => ({
    ...formatSignalResponse(s),
    supersededAt: s.superseded_at,
    supersededBy: s.superseded_by,
  }));

  return jsonResponse({ data: formatted });
}
