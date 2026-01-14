import type {
  JobRecord,
  ApplicationRecord,
  JobResponse,
  ApplicationResponse,
  PublicJobDto,
  PublicJobDetailDto,
} from './types.ts';
import { jsonResponse } from '../_shared/cors.ts';

// Convert snake_case DB record to camelCase API response (for private endpoints)
export function formatJobResponse(job: JobRecord): JobResponse {
  return {
    id: job.id,
    tenantId: job.tenant_id,
    title: job.title,
    description: job.description,
    location: job.location,
    department: job.department,
    isPublic: job.is_public,
    publishAt: job.publish_at,
    expireAt: job.expire_at,
    externalApplyUrl: job.external_apply_url,
    extra: job.extra,
    createdAt: job.created_at,
    updatedAt: job.updated_at,
  };
}

export function formatApplicationResponse(app: ApplicationRecord): ApplicationResponse {
  return {
    id: app.id,
    tenantId: app.tenant_id,
    jobId: app.job_id,
    applicantName: app.applicant_name,
    applicantEmail: app.applicant_email,
    applicantPhone: app.applicant_phone,
    resumeUrl: app.resume_url,
    coverLetter: app.cover_letter,
    status: app.status,
    createdAt: app.created_at,
    updatedAt: app.updated_at,
  };
}

// Format for public job list (snake_case to match NestJS response)
export function formatPublicJobDto(job: JobRecord): PublicJobDto {
  return {
    id: job.id,
    title: job.title,
    department: job.department,
    location: job.location,
    description_excerpt: createDescriptionExcerpt(job.description),
    publish_at: job.publish_at || '',
    updated_at: job.updated_at,
    extra: job.extra,
  };
}

// Format for public job detail (snake_case to match NestJS response)
export function formatPublicJobDetailDto(job: JobRecord): PublicJobDetailDto {
  return {
    id: job.id,
    title: job.title,
    department: job.department,
    location: job.location,
    description: job.description,
    publish_at: job.publish_at || '',
    updated_at: job.updated_at,
    extra: job.extra,
  };
}

// Create description excerpt (max 100 chars with ellipsis)
function createDescriptionExcerpt(description: string | null): string {
  if (!description) return '';
  if (description.length <= 100) return description;
  return description.substring(0, 100) + '...';
}

// Convert single camelCase string to snake_case (for sortBy params)
export function camelToSnake(str: string): string {
  return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
}

// Convert camelCase request body to snake_case for DB
export function toSnakeCase(obj: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) {
    const snakeKey = key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
    result[snakeKey] = value;
  }
  return result;
}

// Error handler with appropriate HTTP status codes
export function handleError(error: unknown): Response {
  const err = error as Error;
  let status = 400;
  let code = 'validation_error';

  if (err.message.includes('not found') || err.message.includes('No rows')) {
    status = 404;
    code = 'not_found';
  } else if (err.message.includes('Unauthorized') || err.message.includes('Invalid or missing token')) {
    status = 401;
    code = 'unauthorized';
  } else if (err.message.includes('Forbidden') || err.message.includes('Missing permission')) {
    status = 403;
    code = 'forbidden';
  } else if (err.message.includes('already exists') || err.message.includes('duplicate')) {
    status = 409;
    code = 'conflict';
  }

  return jsonResponse({ code, message: err.message }, status);
}
