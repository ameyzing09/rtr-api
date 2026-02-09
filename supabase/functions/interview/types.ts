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
  created_at: string;
}

export interface InterviewerAssignmentRecord {
  id: string;
  tenant_id: string;
  round_id: string;
  user_id: string;
  created_at: string;
}

export interface InterviewFeedbackRecord {
  id: string;
  tenant_id: string;
  round_id: string;
  submitted_by: string;
  decision: 'PASS' | 'FAIL' | 'NEUTRAL';
  notes: string | null;
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
  createdAt: string;
  assignments?: InterviewerAssignmentResponse[];
  feedback?: InterviewFeedbackResponse[];
}

export interface InterviewerAssignmentResponse {
  id: string;
  userId: string;
  createdAt: string;
}

export interface InterviewFeedbackResponse {
  id: string;
  submittedBy: string;
  decision: string;
  notes: string | null;
  createdAt: string;
}

export interface MyPendingRoundResponse {
  roundId: string;
  roundType: string;
  sequence: number;
  interviewId: string;
  applicationId: string;
  pipelineStageId: string;
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
}

export interface CreateInterviewDTO {
  pipeline_stage_id: string;
  rounds: CreateInterviewRoundDTO[];
}

export interface SubmitFeedbackDTO {
  decision: 'PASS' | 'FAIL' | 'NEUTRAL';
  notes?: string;
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
