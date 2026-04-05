import type { SupabaseClient } from '@supabase/supabase-js';

// Batch helper — chunks .in() queries to avoid Supabase limits
export async function batchIn<T>(
  client: SupabaseClient,
  table: string,
  column: string,
  ids: string[],
  select: string,
  chunkSize = 50,
): Promise<T[]> {
  if (ids.length === 0) return [];
  const results: T[] = [];
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const { data, error } = await client
      .from(table)
      .select(select)
      .in(column, chunk);
    if (error) {
      throw new Error(`Failed to fetch ${table}: ${error.message}`);
    }
    if (data) results.push(...(data as T[]));
  }
  return results;
}

// Batch helper variant that swallows errors (for timeline best-effort fetches)
export async function batchInSafe<T>(
  client: SupabaseClient,
  table: string,
  column: string,
  ids: string[],
  select: string,
  chunkSize = 50,
): Promise<T[]> {
  if (ids.length === 0) return [];
  const results: T[] = [];
  for (let i = 0; i < ids.length; i += chunkSize) {
    const chunk = ids.slice(i, i + chunkSize);
    const { data, error } = await client
      .from(table)
      .select(select)
      .in(column, chunk);
    if (error) {
      console.warn(`Timeline: failed to fetch ${table}: ${error.message}`);
      continue;
    }
    if (data) results.push(...(data as T[]));
  }
  return results;
}
