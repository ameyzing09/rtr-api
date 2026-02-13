import type { ErrorResponse, PipelineRecord, PipelineResponse, Stage } from './types.ts';

// CORS headers
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-tenant-id, x-request-id',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
};

// CORS preflight response
export function corsResponse(): Response {
  return new Response(null, { status: 200, headers: corsHeaders });
}

// JSON response with CORS headers
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Text response for health check
export function textResponse(text: string, status = 200): Response {
  return new Response(text, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'text/plain' },
  });
}

// Convert snake_case DB record to PascalCase API response (per MIGRATION_SPEC)
export function formatPipelineResponse(pipeline: PipelineRecord): PipelineResponse {
  return {
    ID: pipeline.id,
    TenantID: pipeline.tenant_id,
    Name: pipeline.name,
    Description: pipeline.description,
    Stages: pipeline.stages,
    IsActive: pipeline.is_active,
    IsDeleted: pipeline.is_deleted,
    CreatedBy: pipeline.created_by,
    UpdatedBy: pipeline.updated_by,
    CreatedAt: pipeline.created_at,
    UpdatedAt: pipeline.updated_at,
  };
}

// Convert camelCase request body to snake_case for DB
export function toSnakeCase(obj: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) {
    const snakeKey = key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
    result[snakeKey] = value;
  }
  return result;
}

// Validate stages array
export function validateStages(stages: unknown): stages is Stage[] {
  if (!Array.isArray(stages) || stages.length === 0) {
    return false;
  }
  return stages.every(
    (s) =>
      typeof s === 'object' &&
      s !== null &&
      typeof s.stage === 'string' &&
      s.stage.length >= 1 &&
      s.stage.length <= 100 &&
      typeof s.type === 'string' &&
      s.type.length >= 1 &&
      s.type.length <= 50 &&
      typeof s.conducted_by === 'string' &&
      s.conducted_by.length >= 1 &&
      s.conducted_by.length <= 50,
  );
}

// Validate pipeline name
export function validateName(name: unknown): name is string {
  return typeof name === 'string' && name.length >= 3 && name.length <= 255;
}

// Validate description
export function validateDescription(description: unknown): boolean {
  return description === undefined || description === null ||
    (typeof description === 'string' && description.length <= 1000);
}

// Error handler with spec-compliant format
export function handleError(error: unknown): Response {
  const err = error as Error;
  let status = 400;
  let code = 'validation_error';
  let details: string | undefined;

  const message = err.message || 'An error occurred';

  if (message.includes('not found') || message.includes('No rows')) {
    status = 404;
    code = 'not_found';
  } else if (message.includes('Unauthorized') || message.includes('Invalid or missing token')) {
    status = 401;
    code = 'unauthorized';
  } else if (
    message.includes('Forbidden') || message.includes('Missing permission') || message.includes('role required')
  ) {
    status = 403;
    code = 'forbidden';
  } else if (
    message.includes('already exists') || message.includes('duplicate') || message.includes('unique constraint')
  ) {
    status = 409;
    code = 'conflict';
    details = 'A pipeline with this name already exists for this tenant';
  }

  const errorResponse: ErrorResponse = {
    code,
    message,
    status_code: status,
  };

  if (details) {
    errorResponse.details = details;
  }

  return jsonResponse(errorResponse, status);
}
