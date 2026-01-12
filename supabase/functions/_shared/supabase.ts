import { createClient, SupabaseClient } from '@supabase/supabase-js';

// Get client with user's JWT for RLS-protected queries
export function getSupabaseClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get('Authorization') || '';

  // Use new publishable key (2025) or fall back to legacy anon key
  const publicKey = Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
    || Deno.env.get('SUPABASE_ANON_KEY')!;

  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    publicKey,
    {
      global: { headers: { Authorization: authHeader } },
    }
  );
}

// Admin client for auth operations (bypasses RLS)
export function getSupabaseAdmin(): SupabaseClient {
  // Use new secret key (2025) or fall back to legacy service_role key
  const secretKey = Deno.env.get('SUPABASE_SECRET_KEY')
    || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    secretKey
  );
}
