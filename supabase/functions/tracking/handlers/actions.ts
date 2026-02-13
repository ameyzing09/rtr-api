import type {
  AvailableActionResponse,
  EvaluationRequirement,
  ExecuteActionDTO,
  HandlerContext,
  PipelineStageRecord,
  SignalCondition,
  SignalConditions,
} from '../types.ts';
import { isValidUUID, jsonResponse } from '../utils.ts';

// ============================================================================
// Type for RPC return (matches tracking_state_result composite type with v2 fields)
// ============================================================================
interface TrackingRpcResult {
  id: string;
  application_id: string;
  job_id: string;
  pipeline_id: string;
  current_stage_id: string;
  status: string;
  entered_stage_at: string;
  updated_at: string;
  outcome_type: string;
  is_terminal: boolean;
}

// Format RPC result to API response
function formatRpcResult(
  result: TrackingRpcResult,
  stage: PipelineStageRecord,
) {
  return {
    id: result.id,
    applicationId: result.application_id,
    jobId: result.job_id,
    pipelineId: result.pipeline_id,
    currentStageId: result.current_stage_id,
    currentStageName: stage.stage_name,
    currentStageIndex: stage.order_index,
    status: result.status,
    outcomeType: result.outcome_type,
    isTerminal: result.is_terminal,
    enteredStageAt: result.entered_stage_at,
    createdAt: result.entered_stage_at,
    updatedAt: result.updated_at,
  };
}

// Handle structured error codes from RPC
function handleRpcError(error: { code?: string; message?: string }): never {
  const msg = error.message || 'Unknown error';

  if (error.code === '23505') {
    throw new Error('Application already attached to a pipeline (conflict)');
  }
  if (msg.includes('TENANT_MISMATCH')) {
    throw new Error('Forbidden: Tenant access violation');
  }
  if (msg.includes('NOT_FOUND')) {
    throw new Error('Not found: Application state not found');
  }
  if (msg.includes('TERMINAL_STATUS')) {
    throw new Error('Forbidden: Cannot modify application in terminal status');
  }
  if (msg.includes('INVALID_ACTION')) {
    const detail = msg.split(': ').slice(1).join(': ');
    throw new Error(`Bad request: ${detail}`);
  }
  if (msg.includes('FORBIDDEN')) {
    const detail = msg.split(': ').slice(1).join(': ');
    throw new Error(`Forbidden: ${detail}`);
  }
  if (msg.includes('VALIDATION')) {
    const detail = msg.split(': ').slice(1).join(': ');
    throw new Error(`Bad request: ${detail}`);
  }
  if (msg.includes('EVALUATIONS_INCOMPLETE')) {
    const detail = msg.split(': ').slice(1).join(': ');
    throw new Error(`Evaluations incomplete: ${detail}`);
  }
  if (msg.includes('FEEDBACK_REQUIRED')) {
    const detail = msg.split(': ').slice(1).join(': ');
    throw new Error(`Feedback required: ${detail}`);
  }
  if (msg.includes('INVALID_STATUS')) {
    throw new Error(`Bad request: ${msg.split(': ').slice(1).join(': ')}`);
  }
  if (msg.includes('SIGNALS_NOT_MET')) {
    const detail = msg.split(': ').slice(1).join(': ');
    throw new Error(`Signals not met: ${detail}`);
  }

  throw new Error(msg);
}

// ============================================================================
// POST /applications/:id/act - Execute an action on an application
// ============================================================================
export async function executeAction(ctx: HandlerContext, req: Request): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  const body: ExecuteActionDTO = await req.json();

  // Validate action is provided
  if (!body.action || typeof body.action !== 'string' || body.action.trim() === '') {
    throw new Error('action is required');
  }

  // Normalize action code
  const actionCode = body.action.toUpperCase().trim();

  // Call the atomic RPC with extended parameters for accountability chain
  const { data: result, error: rpcError } = await ctx.supabaseAdmin
    .rpc('execute_action_v2', {
      p_application_id: applicationId,
      p_tenant_id: ctx.tenantId,
      p_user_id: ctx.userId,
      p_action_code: actionCode,
      p_notes: body.notes || null,
      p_override_reason: body.override_reason || null,
      p_reviewed_by: body.reviewed_by || null,
      p_approved_by: body.approved_by || null,
    });

  if (rpcError) {
    handleRpcError(rpcError);
  }

  // Get stage details for response
  const rpcResult = result as TrackingRpcResult;
  const { data: stage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', rpcResult.current_stage_id)
    .single();

  if (stageError || !stage) {
    throw new Error('Current stage not found after action execution');
  }

  return jsonResponse({
    data: formatRpcResult(rpcResult, stage as PipelineStageRecord),
  });
}

// ============================================================================
// GET /applications/:id/actions - Get available actions for current stage
// ============================================================================
export async function getAvailableActions(ctx: HandlerContext): Promise<Response> {
  const applicationId = ctx.pathParts[1];

  if (!isValidUUID(applicationId)) {
    throw new Error('Invalid application ID format');
  }

  // Get application's current state (includes outcome_type + is_terminal)
  const { data: state, error: stateError } = await ctx.supabaseUser
    .from('application_pipeline_state')
    .select('*')
    .eq('application_id', applicationId)
    .eq('tenant_id', ctx.tenantId)
    .single();

  if (stateError || !state) {
    throw new Error(`Tracking state for application ${applicationId} not found`);
  }

  // Get current stage details
  const { data: stage, error: stageError } = await ctx.supabaseAdmin
    .from('pipeline_stages')
    .select('*')
    .eq('id', state.current_stage_id)
    .single();

  if (stageError || !stage) {
    throw new Error('Current stage not found');
  }

  const currentStage = stage as PipelineStageRecord;

  // Check if application is in terminal state (from state row, not status lookup)
  if (state.is_terminal) {
    return jsonResponse({
      data: {
        applicationId: state.application_id,
        currentStageId: currentStage.id,
        currentStageType: currentStage.stage_type,
        currentStageName: currentStage.stage_name,
        status: state.status,
        outcomeType: state.outcome_type,
        isTerminal: true,
        availableActions: [],
      },
    });
  }

  // Get all active actions for this stage_id (not stage_type)
  const { data: actions, error: actionsError } = await ctx.supabaseAdmin
    .from('tenant_stage_actions')
    .select('*')
    .eq('tenant_id', ctx.tenantId)
    .eq('stage_id', state.current_stage_id)
    .eq('is_active', true)
    .order('sort_order');

  if (actionsError) {
    throw new Error(`Failed to fetch actions: ${actionsError.message}`);
  }

  // Get user's capabilities via role_capabilities + user_profiles
  const { data: capabilities, error: capError } = await ctx.supabaseAdmin
    .from('role_capabilities')
    .select('capability')
    .eq('tenant_id', ctx.tenantId)
    .eq('role_name', ctx.userRole || '');

  if (capError) {
    throw new Error(`Failed to fetch capabilities: ${capError.message}`);
  }

  const userCapabilities = new Set(
    (capabilities || []).map((c: { capability: string }) => c.capability),
  );

  // Filter actions by user capabilities
  const capableActions = (actions || []).filter(
    (a: { required_capability: string }) => userCapabilities.has(a.required_capability),
  );

  // Apply HOLD/ACTIVATE guards using outcome_type from state row
  const contextualActions = capableActions.filter(
    (a: { outcome_type: string | null }) => {
      if (a.outcome_type === 'HOLD' && state.outcome_type !== 'ACTIVE') return false;
      if (a.outcome_type === 'ACTIVE' && state.outcome_type !== 'HOLD') return false;
      return true;
    },
  );

  // Check evaluation completion for current stage (stage-level, not per-action)
  const { data: requiredEvals, error: reqEvalsError } = await ctx.supabaseAdmin
    .from('stage_evaluations')
    .select('evaluation_template_id, execution_order, evaluation_templates!inner(id, name)')
    .eq('stage_id', state.current_stage_id)
    .eq('tenant_id', ctx.tenantId)
    .eq('required', true)
    .eq('is_active', true)
    .order('execution_order');

  if (reqEvalsError) {
    throw new Error(`Failed to fetch stage evaluations: ${reqEvalsError.message}`);
  }

  const { data: evalInstances, error: evalInstError } = await ctx.supabaseAdmin
    .from('evaluation_instances')
    .select('id, template_id, stage_id, status')
    .eq('application_id', applicationId)
    .eq('stage_id', state.current_stage_id)
    .eq('tenant_id', ctx.tenantId);

  if (evalInstError) {
    throw new Error(`Failed to fetch evaluation instances: ${evalInstError.message}`);
  }

  const instanceByTemplateStage = new Map(
    (evalInstances || []).map((
      ei: { id: string; template_id: string; stage_id: string; status: string },
    ) => [`${ei.template_id}:${ei.stage_id}`, { id: ei.id, status: ei.status }]),
  );

  const requiredEvaluations: EvaluationRequirement[] = (requiredEvals || []).map(
    (
      se: {
        evaluation_template_id: string;
        evaluation_templates: { id: string; name: string } | { id: string; name: string }[];
      },
    ) => {
      const tmpl = Array.isArray(se.evaluation_templates) ? se.evaluation_templates[0] : se.evaluation_templates;
      const instance = instanceByTemplateStage.get(
        `${se.evaluation_template_id}:${state.current_stage_id}`,
      );
      return {
        templateId: se.evaluation_template_id,
        templateName: tmpl.name,
        completed: instance?.status === 'COMPLETED',
        instanceId: instance?.id ?? null,
        instanceStatus: instance?.status ?? null,
      };
    },
  );

  const evaluationsComplete = requiredEvaluations.length === 0 ||
    requiredEvaluations.every((e) => e.completed);

  // Get signal status for each action that has signal_conditions
  const actionsWithConditions = contextualActions.filter(
    (a: { signal_conditions: unknown }) => a.signal_conditions !== null,
  );

  // Batch fetch signal status for all actions with conditions
  const signalStatusMap: Record<string, { signalsMet: boolean; conditions: SignalCondition[]; logic?: string }> = {};

  for (const action of actionsWithConditions) {
    const a = action as { action_code: string };
    const { data: signalStatus } = await ctx.supabaseAdmin
      .rpc('get_action_signal_status', {
        p_application_id: applicationId,
        p_action_code: a.action_code,
        p_stage_id: state.current_stage_id,
        p_tenant_id: ctx.tenantId,
      });

    if (signalStatus) {
      signalStatusMap[a.action_code] = signalStatus as {
        signalsMet: boolean;
        conditions: SignalCondition[];
        logic?: string;
      };
    }
  }

  // Format response
  const availableActions: AvailableActionResponse[] = contextualActions.map(
    (a: {
      action_code: string;
      display_name: string;
      outcome_type: string | null;
      is_terminal: boolean;
      requires_notes: boolean;
      signal_conditions: { logic: string; conditions: unknown[] } | null;
    }) => {
      const signalStatus = signalStatusMap[a.action_code];

      // Build signal conditions response if action has conditions
      let signalConditions: SignalConditions | undefined;
      if (a.signal_conditions && signalStatus) {
        signalConditions = {
          logic: (signalStatus.logic || a.signal_conditions.logic || 'ALL') as 'ALL' | 'ANY',
          conditions: signalStatus.conditions || [],
        };
      }

      return {
        actionCode: a.action_code,
        displayName: a.display_name,
        outcomeType: a.outcome_type,
        isTerminal: a.is_terminal,
        requiresNotes: a.requires_notes,
        signalConditions,
        signalsMet: signalStatus ? signalStatus.signalsMet : true,
      };
    },
  );

  return jsonResponse({
    data: {
      applicationId: state.application_id,
      currentStageId: currentStage.id,
      currentStageType: currentStage.stage_type,
      currentStageName: currentStage.stage_name,
      status: state.status,
      outcomeType: state.outcome_type,
      isTerminal: false,
      evaluationsComplete,
      requiredEvaluations,
      availableActions,
    },
  });
}

// ============================================================================
// GET /settings/actions - List stage actions for the tenant
// ============================================================================
export async function listStageActions(ctx: HandlerContext): Promise<Response> {
  const { data, error } = await ctx.supabaseAdmin
    .from('tenant_stage_actions')
    .select(`
      id,
      tenant_id,
      stage_id,
      action_code,
      display_name,
      outcome_type,
      moves_to_next_stage,
      is_terminal,
      requires_feedback,
      requires_notes,
      required_capability,
      signal_conditions,
      sort_order,
      is_active,
      pipeline_stages!inner (
        id,
        stage_name,
        stage_type,
        order_index,
        pipeline_id
      )
    `)
    .eq('tenant_id', ctx.tenantId)
    .eq('is_active', true)
    .order('sort_order');

  if (error) {
    throw new Error(`Failed to fetch stage actions: ${error.message}`);
  }

  // Format for API response
  const formatted = (data || []).map((a: Record<string, unknown>) => {
    const stage = a.pipeline_stages as Record<string, unknown>;
    return {
      id: a.id,
      stageId: a.stage_id,
      stageName: stage?.stage_name,
      stageType: stage?.stage_type,
      stageOrderIndex: stage?.order_index,
      pipelineId: stage?.pipeline_id,
      actionCode: a.action_code,
      displayName: a.display_name,
      outcomeType: a.outcome_type,
      movesToNextStage: a.moves_to_next_stage,
      isTerminal: a.is_terminal,
      requiresFeedback: a.requires_feedback,
      requiresNotes: a.requires_notes,
      requiredCapability: a.required_capability,
      signalConditions: a.signal_conditions,
      sortOrder: a.sort_order,
    };
  });

  return jsonResponse({ data: formatted });
}

// ============================================================================
// GET /settings/capabilities - List role capabilities for the tenant
// ============================================================================
export async function listCapabilities(ctx: HandlerContext): Promise<Response> {
  const { data, error } = await ctx.supabaseAdmin
    .from('role_capabilities')
    .select('role_name, capability')
    .eq('tenant_id', ctx.tenantId)
    .order('role_name')
    .order('capability');

  if (error) {
    throw new Error(`Failed to fetch capabilities: ${error.message}`);
  }

  // Group by role_name
  const grouped: Record<string, string[]> = {};
  for (const row of (data || [])) {
    const r = row as { role_name: string; capability: string };
    if (!grouped[r.role_name]) {
      grouped[r.role_name] = [];
    }
    grouped[r.role_name].push(r.capability);
  }

  const formatted = Object.entries(grouped).map(([roleName, capabilities]) => ({
    roleName,
    capabilities,
  }));

  return jsonResponse({ data: formatted });
}
