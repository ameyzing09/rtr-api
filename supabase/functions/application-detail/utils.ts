import type { ErrorResponse } from './types.ts';

// CORS headers
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-tenant-id, x-request-id',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

// Validate UUID format
export function isValidUUID(str: string): boolean {
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
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
  } else if (
    message.includes('Unauthorized') ||
    message.includes('Invalid or missing token')
  ) {
    status = 401;
    code = 'unauthorized';
  } else if (
    message.includes('Forbidden') ||
    message.includes('Missing permission') ||
    message.includes('role required')
  ) {
    status = 403;
    code = 'forbidden';
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
