import type { SupabaseClient, User } from '@supabase/supabase-js';

export interface UserProfile {
  id: string;
  tenant_id: string;
  name: string;
  role: string;
  is_owner: boolean;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface AuthContext {
  user: User;
  profile: UserProfile;
  permissions: string[];
}

export interface HandlerContext {
  supabaseAdmin: SupabaseClient;
  supabaseUser: SupabaseClient;
  url: URL;
  pathParts: string[];
  method: string;
}

export type RouteHandler = (ctx: HandlerContext, req: Request) => Promise<Response>;
