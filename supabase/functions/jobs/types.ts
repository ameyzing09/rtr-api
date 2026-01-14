import type { SupabaseClient } from '@supabase/supabase-js';

// Database record types (snake_case - matches PostgreSQL columns)
export interface JobRecord {
  id: string;
  tenant_id: string;
  title: string;
  description: string | null;
  location: string | null;
  department: string | null;
  is_public: boolean;
  publish_at: string | null;
  expire_at: string | null;
  external_apply_url: string | null;
  extra: Record<string, unknown> | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface ApplicationRecord {
  id: string;
  tenant_id: string;
  job_id: string;
  applicant_name: string;
  applicant_email: string;
  applicant_phone: string | null;
  resume_url: string | null;
  cover_letter: string | null;
  status: 'PENDING' | 'REVIEWED' | 'REJECTED' | 'HIRED';
  created_at: string;
  updated_at: string;
}

// API response types (camelCase - matches UI expectations for private endpoints)
export interface JobResponse {
  id: string;
  tenantId: string;
  title: string;
  description: string | null;
  location: string | null;
  department: string | null;
  isPublic: boolean;
  publishAt: string | null;
  expireAt: string | null;
  externalApplyUrl: string | null;
  extra: Record<string, unknown> | null;
  createdAt: string;
  updatedAt: string;
}

export interface ApplicationResponse {
  id: string;
  tenantId: string;
  jobId: string;
  applicantName: string;
  applicantEmail: string;
  applicantPhone: string | null;
  resumeUrl: string | null;
  coverLetter: string | null;
  status: 'PENDING' | 'REVIEWED' | 'REJECTED' | 'HIRED';
  createdAt: string;
  updatedAt: string;
}

// Public API response types (snake_case - matches NestJS public endpoints)
export interface PublicJobDto {
  id: string;
  title: string;
  department: string | null;
  location: string | null;
  description_excerpt: string;
  publish_at: string;
  updated_at: string;
  extra: Record<string, unknown> | null;
}

export interface PublicJobDetailDto {
  id: string;
  title: string;
  department: string | null;
  location: string | null;
  description: string | null;
  publish_at: string;
  updated_at: string;
  extra: Record<string, unknown> | null;
}

export interface PublicJobsResponse {
  data: PublicJobDto[];
  total: number;
}

export interface PublicApplicationResponse {
  id: string;
  status: 'PENDING' | 'REVIEWED' | 'REJECTED' | 'HIRED';
}

// Handler context
export interface HandlerContext {
  supabaseAdmin: SupabaseClient;
  supabaseUser: SupabaseClient;
  tenantId: string;
  userId?: string;
  userRole?: string;
  pathParts: string[];
  method: string;
  url: URL;
}

// Query parameters
export interface JobListParams {
  title?: string;
  department?: string;
  location?: string;
  isPublic?: string;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
  page?: string;
  limit?: string;
}

export interface PublicJobListParams {
  search?: string;
  department?: string;
  location?: string;
  page?: string;
  pageSize?: string;
}
