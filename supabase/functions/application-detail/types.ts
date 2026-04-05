import type { SupabaseClient } from '@supabase/supabase-js';

// ============================================
// Handler Context
// ============================================

export interface HandlerContext {
  supabaseAdmin: SupabaseClient;
  supabaseUser: SupabaseClient;
  tenantId: string;
  userId: string;
  userRole: string;
  pathParts: string[];
  method: string;
  url: URL;
}

// ============================================
// Database Records (snake_case - matches PostgreSQL)
// ============================================

export interface ApplicationRecord {
  id: string;
  tenant_id: string;
  job_id: string;
  applicant_name: string;
  applicant_email: string;
  applicant_phone: string | null;
  resume_url: string | null;
  cover_letter: string | null;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface JobRecord {
  id: string;
  tenant_id: string;
  title: string;
  department: string | null;
  location: string | null;
}

export interface PipelineStageRecord {
  id: string;
  pipeline_id: string;
  stage_name: string;
  stage_type: string;
  order_index: number;
}

export interface ApplicationPipelineStateRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  job_id: string;
  pipeline_id: string;
  current_stage_id: string;
  status: string;
  outcome_type: string;
  is_terminal: boolean;
  entered_stage_at: string;
  created_at: string;
  updated_at: string;
}

export interface InterviewRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  pipeline_stage_id: string;
  status: string;
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
}

export interface InterviewerAssignmentRecord {
  id: string;
  tenant_id: string;
  round_id: string;
  user_id: string;
}

export interface EvaluationInstanceRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  template_id: string;
  stage_id: string | null;
  interview_round_id: string | null;
  status: string;
  completed_at: string | null;
  created_at: string;
}

export interface EvaluationParticipantRecord {
  id: string;
  evaluation_id: string;
  user_id: string;
  status: string;
  submitted_at: string | null;
}

export interface ApplicationStageHistoryRecord {
  id: string;
  tenant_id: string;
  application_id: string;
  pipeline_id: string;
  from_stage_id: string | null;
  to_stage_id: string | null;
  action: string;
  changed_by: string | null;
  changed_at: string;
  reason: string | null;
}

export interface UserProfileRecord {
  id: string;
  name: string | null;
}

// ============================================
// API Response Types (camelCase)
// ============================================

export interface ViewerContext {
  viewerRole: string;
  isRestricted: boolean;
}

export interface ApplicationResponse {
  id: string;
  status: string;
  createdAt: string;
  updatedAt: string;
  resumeUrl: string | null;
  coverLetter: string | null;
}

export interface CandidateResponse {
  name: string;
  email: string;
  phone: string | null;
}

export interface JobResponse {
  id: string;
  title: string;
  department: string | null;
  location: string | null;
}

export interface TrackingResponse {
  pipelineId: string;
  currentStageId: string;
  currentStageName: string;
  currentStageIndex: number;
  status: string;
  outcomeType: string;
  isTerminal: boolean;
  enteredStageAt: string;
}

export interface InterviewSummary {
  id: string;
  applicationId: string;
  pipelineStageId: string;
  stageName: string | null;
  status: string;
  roundCount: number;
  completedRounds: number;
  interviewers: { userId: string; userName: string | null }[];
  createdAt: string;
}

export interface EvaluationSummary {
  id: string;
  applicationId: string;
  templateId: string;
  templateName: string | null;
  stageId: string | null;
  stageName: string | null;
  status: string;
  participantCount: number;
  submittedCount: number;
  pendingCount: number;
  isInterviewLevel: boolean;
  createdAt: string;
}

export interface TimelineEntry {
  type: string;
  timestamp: string;
  summary: string;
  actorId: string | null;
  actorName: string | null;
  metadata: Record<string, unknown> | null;
}

export interface ApplicationDetailResponse {
  viewerContext: ViewerContext;
  application: ApplicationResponse;
  candidate: CandidateResponse;
  job: JobResponse;
  tracking: TrackingResponse | null;
  interviews: InterviewSummary[];
  evaluations: EvaluationSummary[];
  timeline: TimelineEntry[];
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
