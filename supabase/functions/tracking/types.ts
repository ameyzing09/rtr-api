import type { SupabaseClient } from '@supabase/supabase-js';

// ============================================
// Database Records (snake_case - matches PostgreSQL)
// ============================================

export interface PipelineStageRecord {
  id: string;
  tenant_id: string | null;
  pipeline_id: string;
  stage_name: string;
  stage_type: string;
  conducted_by: string;
  order_index: number;
  metadata: Record<string, unknown> | null;
  created_at: string;
}

export interface ApplicationPipelineStateRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  job_id: string;
  pipeline_id: string;
  current_stage_id: string;
  status: string;  // Denormalized presentation label, derived from outcome_type
  outcome_type: string;  // 'ACTIVE' | 'HOLD' | 'SUCCESS' | 'FAILURE' | 'NEUTRAL'
  is_terminal: boolean;
  entered_stage_at: string;
  created_at: string;
  updated_at: string;
}

export interface ApplicationStageHistoryRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  pipeline_id: string;
  from_stage_id: string | null;
  to_stage_id: string | null;
  action: string;  // Now tenant-configurable via action_code
  changed_by: string | null;
  changed_at: string;
  reason: string | null;
}

export interface ApplicationRecord {
  id: string;
  tenant_id: string;
  job_id: string;
  applicant_name: string;
  applicant_email: string;
  applicant_phone: string | null;
  resume_url: string | null;
  status: string;
  created_at: string;
}

// ============================================
// API Responses (camelCase for internal APIs)
// ============================================

export interface TrackingStateResponse {
  id: string;
  applicationId: string;
  jobId: string;
  pipelineId: string;
  currentStageId: string;
  currentStageName: string;
  currentStageIndex: number;
  status: string;
  outcomeType: string;
  isTerminal: boolean;
  enteredStageAt: string;
  createdAt: string;
  updatedAt: string;
}

export interface StageHistoryResponse {
  id: string;
  applicationId: string;
  pipelineId: string;
  fromStageId: string | null;
  fromStageName: string | null;
  toStageId: string | null;
  toStageName: string | null;
  action: string;
  changedBy: string | null;
  changedAt: string;
  reason: string | null;
}

export interface PipelineStageResponse {
  id: string;
  stageName: string;
  stageType: string;
  conductedBy: string;
  orderIndex: number;
}

export interface BoardStageResponse {
  stage: PipelineStageResponse;
  applications: BoardApplicationResponse[];
  count: number;
}

export interface BoardApplicationResponse {
  applicationId: string;
  applicantName: string;
  applicantEmail: string;
  status: string;
  enteredStageAt: string;
}

export interface PipelineBoardResponse {
  pipelineId: string;
  pipelineName: string;
  stages: BoardStageResponse[];
  totalApplications: number;
}

// ============================================
// Request DTOs
// ============================================

export interface AttachToPipelineDTO {
  pipeline_id?: string;  // Optional - uses job's assigned pipeline
  tenant_id?: string;    // For service role calls only
}

export interface MoveStageDTO {
  to_stage_id: string;
  reason?: string;
}

export interface UpdateStatusDTO {
  status: string;  // Now tenant-configurable, validated by RPC
  reason?: string;
}

// ============================================
// Action Engine DTOs & Responses
// ============================================

// Extended ExecuteActionDTO with accountability parameters
export interface ExecuteActionDTO {
  action: string;
  notes?: string;
  override_reason?: string;   // Required if bypassing rules
  reviewed_by?: string;       // Required if feedback-gated
  approved_by?: string;       // Required if forcing past block
}

// Signal condition types (used by action engine for signal gate display)
export interface SignalCondition {
  signal: string;
  operator: '=' | '!=' | '>' | '>=' | '<' | '<=';
  value: unknown;
  onMissing: 'BLOCK' | 'ALLOW' | 'WARN';
  currentValue: unknown | null;
  met: boolean;
  warning?: boolean;
  reason?: string;
}

export interface SignalConditions {
  logic: 'ALL' | 'ANY';
  conditions: SignalCondition[];
}

export interface AvailableActionResponse {
  actionCode: string;
  displayName: string;
  outcomeType: string | null;
  isTerminal: boolean;
  requiresFeedback: boolean;
  requiresNotes: boolean;
  feedbackSubmitted: boolean;
  signalConditions?: SignalConditions;
  signalsMet: boolean;
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
// Tenant-Configurable Status Record
// ============================================

export interface TenantStatusRecord {
  id: string;
  tenant_id: string;
  status_code: string;
  display_name: string;
  action_code: string;
  outcome_type: string;  // 'ACTIVE' | 'HOLD' | 'SUCCESS' | 'FAILURE' | 'NEUTRAL'
  is_terminal: boolean;
  is_active: boolean;
  sort_order: number;
  color_hex: string | null;
  created_at: string;
  updated_at: string;
}

// For API responses (camelCase)
export interface TenantStatusResponse {
  id: string;
  statusCode: string;
  displayName: string;
  actionCode: string;
  outcomeType: string;
  isTerminal: boolean;
  sortOrder: number;
  colorHex: string | null;
}

// Request DTOs for status management
export interface CreateStatusDTO {
  status_code: string;
  display_name: string;
  action_code?: string;
  outcome_type?: string;  // 'ACTIVE' | 'HOLD' | 'SUCCESS' | 'FAILURE' | 'NEUTRAL'
  is_terminal?: boolean;
  sort_order?: number;
  color_hex?: string;
}

export interface UpdateTenantStatusDTO {
  display_name?: string;
  action_code?: string;
  outcome_type?: string;  // 'ACTIVE' | 'HOLD' | 'SUCCESS' | 'FAILURE' | 'NEUTRAL'
  is_terminal?: boolean;
  sort_order?: number;
  color_hex?: string;
}
