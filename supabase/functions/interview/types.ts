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
// Database Records (snake_case - matches PostgreSQL)
// ============================================

export interface InterviewRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  pipeline_stage_id: string;
  status: 'PLANNED' | 'IN_PROGRESS' | 'CANCELLED';
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface InterviewRoundRecord {
  id: string;
  tenant_id: string;
  interview_id: string;
  round_type: string;
  sequence: number;
  evaluation_instance_id: string | null;
  created_at: string;
}

export interface InterviewerAssignmentRecord {
  id: string;
  tenant_id: string;
  round_id: string;
  user_id: string;
  created_at: string;
}

// ============================================
// API Responses (camelCase)
// ============================================

export interface InterviewResponse {
  id: string;
  applicationId: string;
  pipelineStageId: string;
  status: string;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
  rounds?: InterviewRoundResponse[];
}

export interface InterviewRoundResponse {
  id: string;
  roundType: string;
  sequence: number;
  evaluationInstanceId: string | null;
  createdAt: string;
  assignments?: InterviewerAssignmentResponse[];
}

export interface InterviewerAssignmentResponse {
  id: string;
  userId: string;
  createdAt: string;
}

export interface MyPendingRoundResponse {
  roundId: string;
  interviewId: string;
  applicationId: string;
  applicantName: string;
  jobTitle: string;
  stage: { id: string; name: string };
  roundType: string;
  roundComplete: boolean;
  evaluationInstanceId: string;
  interviewStatus: string;
  assignedAt: string;
}

// ============================================
// Request DTOs
// ============================================

export interface CreateInterviewRoundDTO {
  round_type: string;
  sequence: number;
  interviewer_ids: string[];
  evaluation_template_id: string;
}

export interface CreateInterviewDTO {
  pipeline_stage_id: string;
  rounds: CreateInterviewRoundDTO[];
}

export interface UpdateInterviewDTO {
  status: 'CANCELLED';
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
