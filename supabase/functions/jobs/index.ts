import { getSupabaseClient } from '../_shared/supabase.ts';
import { corsResponse, jsonResponse } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return corsResponse();
  }

  const url = new URL(req.url);
  const pathParts = url.pathname.split('/').filter(Boolean);
  // pathParts: ['jobs'] or ['jobs', ':id']
  const id = pathParts.length > 1 ? pathParts[1] : null;
  const method = req.method;
  const supabase = getSupabaseClient(req);

  try {
    // GET /jobs - List all jobs (RLS filters by tenant automatically!)
    if (!id && method === 'GET') {
      const { data, error } = await supabase
        .from('jobs')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return jsonResponse({ success: true, data, count: data.length });
    }

    // POST /jobs - Create job
    if (!id && method === 'POST') {
      const body = await req.json();
      const { data: { user } } = await supabase.auth.getUser();
      const { data, error } = await supabase
        .from('jobs')
        .insert({ ...body, created_by: user?.id })
        .select()
        .single();
      if (error) throw error;
      return jsonResponse({ success: true, data }, 201);
    }

    // Routes with ID: /jobs/:id
    if (id) {
      // GET /jobs/:id
      if (method === 'GET') {
        const { data, error } = await supabase
          .from('jobs')
          .select('*')
          .eq('id', id)
          .single();
        if (error) throw error;
        return jsonResponse({ success: true, data });
      }

      // PUT /jobs/:id
      if (method === 'PUT') {
        const body = await req.json();
        const { data, error } = await supabase
          .from('jobs')
          .update({ ...body, updated_at: new Date().toISOString() })
          .eq('id', id)
          .select()
          .single();
        if (error) throw error;
        return jsonResponse({ success: true, data });
      }

      // DELETE /jobs/:id
      if (method === 'DELETE') {
        const { error } = await supabase.from('jobs').delete().eq('id', id);
        if (error) throw error;
        return jsonResponse({ success: true, message: 'Job deleted' });
      }
    }

    return jsonResponse({ success: false, error: 'Not found' }, 404);
  } catch (error) {
    return jsonResponse({ success: false, error: (error as Error).message }, 400);
  }
});
