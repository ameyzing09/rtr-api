import type { SupabaseClient } from '@supabase/supabase-js';

// ============================================
// Handler Context
// ============================================

export interface HandlerContext {
  supabaseAdmin: SupabaseClient;
  supabaseUser: SupabaseClient;
  tenantId: string;
  userId?: string;
  userRole?: string;
  pathParts: string[];
  method: string;
  url: URL;
  isServiceRole?: boolean;
}

// ============================================
// Signal Definition (in template schema)
// ============================================

export interface SignalDefinition {
  key: string;
  type: 'boolean' | 'integer' | 'float' | 'text';
  label: string;
  min?: number;
  max?: number;
  aggregation?: 'MAJORITY' | 'UNANIMOUS' | 'ANY' | 'AVERAGE' | null;
}

// ============================================
// Database Records (snake_case - matches PostgreSQL)
// ============================================

export interface EvaluationTemplateRecord {
  id: string;
  tenant_id: string;
  name: string;
  description: string | null;
  version: number;
  is_latest: boolean;
  superseded_by: string | null;
  participant_type: 'SINGLE' | 'PANEL' | 'SEQUENTIAL';
  signal_schema: SignalDefinition[];
  default_aggregation: 'MAJORITY' | 'UNANIMOUS' | 'ANY' | 'AVERAGE';
  is_active: boolean;
  created_by: string | null;
  created_at: string;
}

export interface EvaluationInstanceRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  template_id: string;
  stage_id: string | null;
  status: 'PENDING' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED';
  scheduled_at: string | null;
  completed_at: string | null;
  force_completed: boolean;
  force_complete_note: string | null;
  force_completed_by: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface EvaluationParticipantRecord {
  id: string;
  tenant_id: string;
  evaluation_id: string;
  user_id: string;
  status: 'PENDING' | 'SUBMITTED' | 'DECLINED';
  submitted_at: string | null;
  created_at: string;
}

export interface EvaluationResponseRecord {
  id: string;
  tenant_id: string;
  participant_id: string;
  response_data: Record<string, unknown>;
  submitted_at: string;
}

export interface ApplicationSignalRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  signal_key: string;
  signal_type: 'boolean' | 'integer' | 'float' | 'text';
  signal_value_text: string | null;
  signal_value_numeric: number | null;
  signal_value_boolean: boolean | null;
  source_type: 'EVALUATION' | 'MANUAL' | 'SYSTEM';
  source_id: string | null;
  set_by: string | null;
  set_at: string;
  superseded_at: string | null;
  superseded_by: string | null;
}

export interface ActionExecutionLogRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  action_code: string;
  stage_id: string | null;
  executed_by: string;
  executed_at: string;
  signal_snapshot: Record<string, SignalSnapshotValue>;
  conditions_evaluated: ConditionEvaluationResult[];
  decision_note: string | null;
  override_reason: string | null;
  reviewed_by: string | null;
  approved_by: string | null;
  outcome_type: string | null;
  is_terminal: boolean | null;
  from_stage_id: string | null;
  to_stage_id: string | null;
}

export interface SignalSnapshotValue {
  value: string | null;
  type: string;
  set_at: string;
  set_by: string | null;
  source_type: string;
  source_id: string | null;
}

export interface ConditionEvaluationResult {
  signal: string;
  operator: string;
  expected: unknown;
  actual: unknown;
  met: boolean;
  warning?: boolean;
  reason?: string;
  on_missing?: string;
}

// ============================================
// API Responses (camelCase for internal APIs)
// ============================================

export interface EvaluationTemplateResponse {
  id: string;
  name: string;
  description: string | null;
  version: number;
  isLatest: boolean;
  participantType: 'SINGLE' | 'PANEL' | 'SEQUENTIAL';
  signalSchema: SignalDefinition[];
  defaultAggregation: 'MAJORITY' | 'UNANIMOUS' | 'ANY' | 'AVERAGE';
  isActive: boolean;
  createdAt: string;
}

export interface EvaluationInstanceResponse {
  id: string;
  applicationId: string;
  templateId: string;
  templateName?: string;
  stageId: string | null;
  stageName?: string | null;
  status: 'PENDING' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED';
  scheduledAt: string | null;
  completedAt: string | null;
  forceCompleted: boolean;
  participantCount?: number;
  submittedCount?: number;
  createdAt: string;
  updatedAt: string;
}

export interface EvaluationParticipantResponse {
  id: string;
  evaluationId: string;
  userId: string;
  userName?: string;
  userEmail?: string;
  status: 'PENDING' | 'SUBMITTED' | 'DECLINED';
  submittedAt: string | null;
  createdAt: string;
}

export interface EvaluationResponseResponse {
  id: string;
  participantId: string;
  responseData: Record<string, unknown>;
  submittedAt: string;
}

export interface ApplicationSignalResponse {
  id: string;
  applicationId: string;
  signalKey: string;
  signalType: 'boolean' | 'integer' | 'float' | 'text';
  value: string | number | boolean | null;
  sourceType: 'EVALUATION' | 'MANUAL' | 'SYSTEM';
  sourceId: string | null;
  setBy: string | null;
  setAt: string;
}

export interface ActionExecutionLogResponse {
  id: string;
  applicationId: string;
  actionCode: string;
  stageId: string | null;
  stageName?: string | null;
  executedBy: string;
  executedByEmail?: string;
  executedAt: string;
  signalSnapshot: Record<string, SignalSnapshotValue>;
  conditionsEvaluated: ConditionEvaluationResult[];
  decisionNote: string | null;
  overrideReason: string | null;
  reviewedBy: string | null;
  reviewedByEmail?: string;
  approvedBy: string | null;
  approvedByEmail?: string;
  outcomeType: string | null;
  isTerminal: boolean | null;
  fromStageId: string | null;
  fromStageName?: string | null;
  toStageId: string | null;
  toStageName?: string | null;
}

// ============================================
// Request DTOs
// ============================================

export interface CreateEvaluationTemplateDTO {
  name: string;
  description?: string;
  participant_type?: 'SINGLE' | 'PANEL' | 'SEQUENTIAL';
  signal_schema: SignalDefinition[];
  default_aggregation?: 'MAJORITY' | 'UNANIMOUS' | 'ANY' | 'AVERAGE';
}

export interface UpdateEvaluationTemplateDTO {
  name?: string;
  description?: string;
  participant_type?: 'SINGLE' | 'PANEL' | 'SEQUENTIAL';
  signal_schema?: SignalDefinition[];
  default_aggregation?: 'MAJORITY' | 'UNANIMOUS' | 'ANY' | 'AVERAGE';
  is_active?: boolean;
}

export interface CreateEvaluationInstanceDTO {
  template_id: string;
  stage_id?: string;
  scheduled_at?: string;
  participant_ids?: string[];  // Optional initial participants
}

export interface AddParticipantDTO {
  user_id: string;
}

export interface SubmitResponseDTO {
  response_data: Record<string, unknown>;
}

export interface CompleteEvaluationDTO {
  force?: boolean;
  force_note?: string;
}

export interface SetManualSignalDTO {
  signal_key: string;
  signal_type: 'boolean' | 'integer' | 'float' | 'text';
  value: string;
  note?: string;
}

// ============================================
// Error Response
// ============================================

export interface ErrorResponse {
  code: string;
  message: string;
  status_code: number;
  details?: string;
}
