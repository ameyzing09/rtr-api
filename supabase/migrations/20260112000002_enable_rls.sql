-- RTR API Row Level Security (RLS) Policies
-- Multi-tenant isolation via tenant_id

------------------------------------------------------------
-- ENABLE RLS ON ALL TABLES
------------------------------------------------------------
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipeline_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidate_stage_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE stage_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

------------------------------------------------------------
-- HELPER FUNCTION: Get user's tenant_id from JWT
------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_tenant_id()
RETURNS UUID AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID,
    (SELECT tenant_id FROM public.user_profiles WHERE id = auth.uid())
  );
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

------------------------------------------------------------
-- TENANTS POLICIES
------------------------------------------------------------
-- Users can only view their own tenant
CREATE POLICY "Users can view own tenant" ON tenants
  FOR SELECT USING (id = public.get_tenant_id());

-- Service role can manage all tenants (for admin operations)
CREATE POLICY "Service role full access to tenants" ON tenants
  FOR ALL USING (auth.role() = 'service_role');

------------------------------------------------------------
-- JOBS POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant jobs" ON jobs
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant jobs" ON jobs
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant jobs" ON jobs
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can delete own tenant jobs" ON jobs
  FOR DELETE USING (tenant_id = public.get_tenant_id());

-- Public jobs can be viewed by anyone (for job board)
CREATE POLICY "Anyone can view public jobs" ON jobs
  FOR SELECT USING (is_public = TRUE AND publish_at <= NOW() AND (expire_at IS NULL OR expire_at > NOW()));

------------------------------------------------------------
-- APPLICATIONS POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant applications" ON applications
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant applications" ON applications
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant applications" ON applications
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can delete own tenant applications" ON applications
  FOR DELETE USING (tenant_id = public.get_tenant_id());

------------------------------------------------------------
-- USER PROFILES POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant profiles" ON user_profiles
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (id = auth.uid());

CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (id = auth.uid());

------------------------------------------------------------
-- PIPELINES POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant pipelines" ON pipelines
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant pipelines" ON pipelines
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant pipelines" ON pipelines
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can delete own tenant pipelines" ON pipelines
  FOR DELETE USING (tenant_id = public.get_tenant_id());

------------------------------------------------------------
-- PIPELINE ASSIGNMENTS POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant pipeline assignments" ON pipeline_assignments
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant pipeline assignments" ON pipeline_assignments
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant pipeline assignments" ON pipeline_assignments
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can delete own tenant pipeline assignments" ON pipeline_assignments
  FOR DELETE USING (tenant_id = public.get_tenant_id());

------------------------------------------------------------
-- CANDIDATE STAGE PROGRESS POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant candidate progress" ON candidate_stage_progress
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant candidate progress" ON candidate_stage_progress
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant candidate progress" ON candidate_stage_progress
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

------------------------------------------------------------
-- STAGE FEEDBACK POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant stage feedback" ON stage_feedback
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant stage feedback" ON stage_feedback
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant stage feedback" ON stage_feedback
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

------------------------------------------------------------
-- TENANT SETTINGS POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant settings" ON tenant_settings
  FOR SELECT USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can update own tenant settings" ON tenant_settings
  FOR UPDATE USING (tenant_id = public.get_tenant_id());

CREATE POLICY "Users can insert own tenant settings" ON tenant_settings
  FOR INSERT WITH CHECK (tenant_id = public.get_tenant_id());

------------------------------------------------------------
-- SUBSCRIPTIONS POLICIES
------------------------------------------------------------
CREATE POLICY "Users can view own tenant subscription" ON subscriptions
  FOR SELECT USING (tenant_id = public.get_tenant_id());

-- Only service role can modify subscriptions (billing system)
CREATE POLICY "Service role manages subscriptions" ON subscriptions
  FOR ALL USING (auth.role() = 'service_role');

------------------------------------------------------------
-- AUDIT LOGS POLICIES
------------------------------------------------------------
-- Users can view audit logs for their tenant
CREATE POLICY "Users can view own tenant audit logs" ON audit_logs
  FOR SELECT USING (target_tenant_id = public.get_tenant_id() OR actor_tenant_id = public.get_tenant_id());

-- Only service role can insert audit logs
CREATE POLICY "Service role inserts audit logs" ON audit_logs
  FOR INSERT WITH CHECK (auth.role() = 'service_role');
