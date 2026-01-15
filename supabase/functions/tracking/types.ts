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
  status: 'ACTIVE' | 'HIRED' | 'REJECTED' | 'WITHDRAWN' | 'ON_HOLD';
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
  action: 'MOVE' | 'REJECT' | 'HIRE' | 'WITHDRAW' | 'HOLD' | 'ACTIVATE';
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
  status: 'HIRED' | 'REJECTED' | 'WITHDRAWN' | 'ON_HOLD' | 'ACTIVE';
  reason?: string;
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

// Terminal statuses that block further stage moves
export const TERMINAL_STATUSES = ['HIRED', 'REJECTED', 'WITHDRAWN'] as const;
export type TerminalStatus = typeof TERMINAL_STATUSES[number];
