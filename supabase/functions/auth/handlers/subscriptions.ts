import type { HandlerContext } from '../types.ts';
import { jsonResponse } from '../../_shared/cors.ts';
import { requirePermission } from '../middleware.ts';

// GET /admin/tenant/:id/subscription - Get subscription
export async function getSubscription(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:read');
  const tenantId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('subscriptions')
    .select('*')
    .eq('tenant_id', tenantId)
    .single();
  if (error) throw new Error('Subscription not found');

  return jsonResponse(data);
}

// POST /admin/tenant/:id/subscription/activate
export async function activateSubscription(ctx: HandlerContext, req: Request): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const tenantId = ctx.pathParts[2];
  const { billing_cycle, amount_cents } = await req.json();

  if (!billing_cycle) {
    throw new Error('billing_cycle is required');
  }

  const now = new Date();
  const periodEnd = billing_cycle === 'ANNUAL'
    ? new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000)
    : new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

  const { data, error } = await ctx.supabaseAdmin
    .from('subscriptions')
    .update({
      status: 'ACTIVE',
      billing_cycle,
      amount_cents: amount_cents || 0,
      period_start: now.toISOString(),
      period_end: periodEnd.toISOString(),
      next_renewal_at: periodEnd.toISOString(),
      trial_ends_at: null,
    })
    .eq('tenant_id', tenantId)
    .select()
    .single();
  if (error) throw error;

  return jsonResponse(data);
}

// POST /admin/tenant/:id/subscription/suspend
export async function suspendSubscription(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const tenantId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('subscriptions')
    .update({ status: 'SUSPENDED' })
    .eq('tenant_id', tenantId)
    .select()
    .single();
  if (error) throw error;

  await ctx.supabaseAdmin.from('tenants').update({ status: 'SUSPENDED' }).eq('id', tenantId);

  return jsonResponse(data);
}

// POST /admin/tenant/:id/subscription/resume
export async function resumeSubscription(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const tenantId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('subscriptions')
    .update({ status: 'ACTIVE' })
    .eq('tenant_id', tenantId)
    .select()
    .single();
  if (error) throw error;

  await ctx.supabaseAdmin.from('tenants').update({ status: 'ACTIVE' }).eq('id', tenantId);

  return jsonResponse(data);
}

// POST /admin/tenant/:id/subscription/cancel
export async function cancelSubscription(ctx: HandlerContext): Promise<Response> {
  await requirePermission(ctx.supabaseUser, ctx.supabaseAdmin, 'tenant:update');
  const tenantId = ctx.pathParts[2];

  const { data, error } = await ctx.supabaseAdmin
    .from('subscriptions')
    .update({
      status: 'CANCELED',
      canceled_at: new Date().toISOString(),
    })
    .eq('tenant_id', tenantId)
    .select()
    .single();
  if (error) throw error;

  return jsonResponse(data);
}
