import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  ApplicationRecord,
  PipelineStageRecord,
  TimelineEntry,
  UserProfileRecord,
} from '../types.ts';
import { batchInSafe } from './_shared.ts';

// Resolve user names from IDs using batch fetch
async function resolveUserNames(
  supabaseAdmin: SupabaseClient,
  userIds: Set<string>,
): Promise<Map<string, string>> {
  const usersMap = new Map<string, string>();
  if (userIds.size === 0) return usersMap;

  const profiles = await batchInSafe<UserProfileRecord>(
    supabaseAdmin,
    'user_profiles',
    'id',
    Array.from(userIds),
    'id, name',
  );

  for (const p of profiles) {
    usersMap.set(p.id, p.name ?? 'Unknown');
  }

  return usersMap;
}

// Resolve stage names from IDs using batch fetch
async function resolveStageNames(
  supabaseAdmin: SupabaseClient,
  stageIds: Set<string>,
): Promise<Map<string, string>> {
  const stagesMap = new Map<string, string>();
  if (stageIds.size === 0) return stagesMap;

  const stages = await batchInSafe<PipelineStageRecord>(
    supabaseAdmin,
    'pipeline_stages',
    'id',
    Array.from(stageIds),
    'id, pipeline_id, stage_name, stage_type, order_index',
  );

  for (const s of stages) {
    stagesMap.set(s.id, s.stage_name);
  }

  return stagesMap;
}

// Fetch full timeline entries for HR/Admin view
export async function fetchTimelineEntries(
  supabaseAdmin: SupabaseClient,
  applicationId: string,
  tenantId: string,
  application: ApplicationRecord,
  limit: number,
): Promise<TimelineEntry[]> {
  const entries: TimelineEntry[] = [];
  const userIdsToResolve = new Set<string>();
  const stageIdsToResolve = new Set<string>();

  // Source 1: Application created
  entries.push({
    type: 'APPLICATION_CREATED',
    timestamp: application.created_at,
    summary: `Application submitted by ${application.applicant_name}`,
    actorId: null,
    actorName: application.applicant_name,
    metadata: null,
  });

  // Source 2: Stage transitions
  try {
    const { data: history } = await supabaseAdmin
      .from('application_stage_history')
      .select('from_stage_id, to_stage_id, action, changed_by, changed_at, reason')
      .eq('application_id', applicationId)
      .eq('tenant_id', tenantId)
      .order('changed_at', { ascending: false });

    for (const h of (history || [])) {
      if (h.from_stage_id) stageIdsToResolve.add(h.from_stage_id);
      if (h.to_stage_id) stageIdsToResolve.add(h.to_stage_id);
      if (h.changed_by) userIdsToResolve.add(h.changed_by);

      entries.push({
        type: 'STAGE_TRANSITION',
        timestamp: h.changed_at,
        summary: `Stage transition: ${h.action}`,
        actorId: h.changed_by ?? null,
        actorName: null, // resolved below
        metadata: {
          fromStageId: h.from_stage_id,
          toStageId: h.to_stage_id,
          action: h.action,
          reason: h.reason,
        },
      });
    }
  } catch (e) {
    console.warn('Timeline: failed to fetch stage history', (e as Error).message);
  }

  // Source 3: Interviews created / cancelled / completed
  try {
    const { data: interviews } = await supabaseAdmin
      .from('interviews')
      .select('id, status, created_by, created_at, updated_at')
      .eq('application_id', applicationId)
      .eq('tenant_id', tenantId);

    for (const interview of (interviews || [])) {
      if (interview.created_by) userIdsToResolve.add(interview.created_by);

      entries.push({
        type: 'INTERVIEW_CREATED',
        timestamp: interview.created_at,
        summary: 'Interview created',
        actorId: interview.created_by ?? null,
        actorName: null,
        metadata: { interviewId: interview.id },
      });

      if (interview.status === 'CANCELLED') {
        entries.push({
          type: 'INTERVIEW_CANCELLED',
          timestamp: interview.updated_at,
          summary: 'Interview cancelled',
          actorId: null,
          actorName: null,
          metadata: { interviewId: interview.id },
        });
      }

      if (interview.status === 'COMPLETED') {
        entries.push({
          type: 'INTERVIEW_COMPLETED',
          timestamp: interview.updated_at,
          summary: 'Interview completed',
          actorId: null,
          actorName: null,
          metadata: { interviewId: interview.id },
        });
      }
    }
  } catch (e) {
    console.warn('Timeline: failed to fetch interviews', (e as Error).message);
  }

  // Source 4: Evaluation submissions
  try {
    const { data: evalInstances } = await supabaseAdmin
      .from('evaluation_instances')
      .select('id, status, completed_at')
      .eq('application_id', applicationId)
      .eq('tenant_id', tenantId);

    const evalIds = (evalInstances || []).map((e: { id: string }) => e.id);

    if (evalIds.length > 0) {
      // Submitted participants
      const { data: submissions } = await supabaseAdmin
        .from('evaluation_participants')
        .select('evaluation_id, user_id, submitted_at')
        .in('evaluation_id', evalIds)
        .eq('status', 'SUBMITTED');

      for (const sub of (submissions || [])) {
        if (sub.user_id) userIdsToResolve.add(sub.user_id);
        if (sub.submitted_at) {
          entries.push({
            type: 'EVALUATION_SUBMITTED',
            timestamp: sub.submitted_at,
            summary: 'Evaluation submitted',
            actorId: sub.user_id ?? null,
            actorName: null,
            metadata: { evaluationId: sub.evaluation_id },
          });
        }
      }

      // Completed instances
      for (const inst of (evalInstances || [])) {
        if (inst.status === 'COMPLETED' && inst.completed_at) {
          entries.push({
            type: 'EVALUATION_COMPLETED',
            timestamp: inst.completed_at,
            summary: 'Evaluation completed',
            actorId: null,
            actorName: null,
            metadata: { evaluationId: inst.id },
          });
        }
      }
    }
  } catch (e) {
    console.warn('Timeline: failed to fetch evaluations', (e as Error).message);
  }

  // Resolve user names and stage names in parallel
  const [usersMap, stagesMap] = await Promise.all([
    resolveUserNames(supabaseAdmin, userIdsToResolve),
    resolveStageNames(supabaseAdmin, stageIdsToResolve),
  ]);

  // Enrich entries with resolved names (immutable — produce new objects)
  const enriched = entries.map((entry) => {
    const enrichedMeta = entry.metadata
      ? {
          ...entry.metadata,
          ...(entry.metadata.fromStageId && typeof entry.metadata.fromStageId === 'string'
            ? { fromStageName: stagesMap.get(entry.metadata.fromStageId) ?? null }
            : {}),
          ...(entry.metadata.toStageId && typeof entry.metadata.toStageId === 'string'
            ? { toStageName: stagesMap.get(entry.metadata.toStageId) ?? null }
            : {}),
        }
      : null;

    return {
      ...entry,
      actorName: (entry.actorId && !entry.actorName)
        ? usersMap.get(entry.actorId) ?? null
        : entry.actorName,
      metadata: enrichedMeta,
    };
  });

  // Sort by timestamp descending and apply limit
  const sorted = [...enriched].sort(
    (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime(),
  );
  return sorted.slice(0, limit);
}

// Build restricted timeline for INTERVIEWER — only interview-related events
export async function buildRestrictedTimeline(
  supabaseAdmin: SupabaseClient,
  applicationId: string,
  tenantId: string,
  limit: number,
): Promise<TimelineEntry[]> {
  const entries: TimelineEntry[] = [];
  const userIdsToResolve = new Set<string>();

  try {
    const { data: interviews } = await supabaseAdmin
      .from('interviews')
      .select('id, status, created_by, created_at, updated_at')
      .eq('application_id', applicationId)
      .eq('tenant_id', tenantId);

    for (const interview of (interviews || [])) {
      if (interview.created_by) userIdsToResolve.add(interview.created_by);

      entries.push({
        type: 'INTERVIEW_CREATED',
        timestamp: interview.created_at,
        summary: 'Interview created',
        actorId: interview.created_by ?? null,
        actorName: null,
        metadata: { interviewId: interview.id },
      });

      if (interview.status === 'CANCELLED') {
        entries.push({
          type: 'INTERVIEW_CANCELLED',
          timestamp: interview.updated_at,
          summary: 'Interview cancelled',
          actorId: null,
          actorName: null,
          metadata: { interviewId: interview.id },
        });
      }

      if (interview.status === 'COMPLETED') {
        entries.push({
          type: 'INTERVIEW_COMPLETED',
          timestamp: interview.updated_at,
          summary: 'Interview completed',
          actorId: null,
          actorName: null,
          metadata: { interviewId: interview.id },
        });
      }
    }
  } catch (e) {
    console.warn('Timeline: failed to fetch interviews for restricted view', (e as Error).message);
  }

  // Resolve user names
  const usersMap = await resolveUserNames(supabaseAdmin, userIdsToResolve);
  for (const entry of entries) {
    if (entry.actorId && !entry.actorName) {
      entry.actorName = usersMap.get(entry.actorId) ?? null;
    }
  }

  entries.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
  return entries.slice(0, limit);
}
