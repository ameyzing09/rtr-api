import type { SupabaseClient } from '@supabase/supabase-js';

// Stage structure (same in DB and response)
export interface Stage {
  stage: string;
  type: string;
  conducted_by: string;
  metadata?: Record<string, unknown>;
}

// Database Records (snake_case - matches PostgreSQL)
export interface PipelineRecord {
  id: string;
  tenant_id: string;
  name: string;
  description: string | null;
  stages: Stage[];
  is_active: boolean;
  is_deleted: boolean;
  created_by: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface PipelineAssignmentRecord {
  id: string;
  tenant_id: string;
  pipeline_id: string;
  job_id: string;
  assigned_by: string | null;
  is_deleted: boolean;
  created_at: string;
  updated_at: string;
}

// API Response (PascalCase - per MIGRATION_SPEC)
export interface PipelineResponse {
  ID: string;
  TenantID: string;
  Name: string;
  Description: string | null;
  Stages: Stage[];
  IsActive: boolean;
  IsDeleted: boolean;
  CreatedBy: string | null;
  UpdatedBy: string | null;
  CreatedAt: string;
  UpdatedAt: string;
}

// Error Response (per MIGRATION_SPEC)
export interface ErrorResponse {
  code: string;
  message: string;
  status_code: number;
  details?: string;
}

// Request DTOs
export interface CreatePipelineDTO {
  name: string;
  description?: string;
  stages: Stage[];
  extra?: Record<string, unknown>;
}

export interface UpdatePipelineDTO {
  name?: string;
  description?: string;
  stages?: Stage[];
}

export interface PipelineAssignmentDTO {
  pipeline_id?: string; // Optional - uses default if not provided
  job_id: string;
  tenant_id?: string; // For internal service calls
}

// Handler Context
export interface HandlerContext {
  supabaseAdmin: SupabaseClient;
  supabaseUser: SupabaseClient;
  tenantId: string;
  userId?: string;
  userRole?: string;
  pathParts: string[];
  method: string;
  url: URL;
  isServiceRole?: boolean; // True when called internally with service role key
}
